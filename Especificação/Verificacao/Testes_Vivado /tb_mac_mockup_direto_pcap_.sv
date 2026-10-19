`timescale 1ns/1ps

// Testbench do DUT mockup.
// Le diretamente um arquivo PCAP binario, sem TXT intermediario.
//
// Interface AXI-Stream:
//   rx_axis_tdata  : 64 bits
//   rx_axis_tkeep  : 8 bits
//   rx_axis_tvalid : 1 bit
//   rx_axis_tlast  : 1 bit
//   rx_axis_tuser  : 1 bit
//
// Timestamp IEEE 1588 ToD:
//   tsu_timestamp[79:32] = Seconds (48 bits)
//   tsu_timestamp[31:0]  = Nanoseconds (32 bits)

module tb_mac_mockup;

    // Caminhos dos arquivos
    localparam string PCAP_FILE =
        "teste_bia_dani.pcap";

    localparam string PCAP_FILE_RELATIVE_ALT =
        "teste_bia_dani (1).pcap";

    localparam string PCAP_FILE_ABSOLUTE =
        "C:/Users/Dell/OneDrive/Documentos/teste_dani/teste_bia_dani.pcap";

    localparam string PCAP_FILE_ABSOLUTE_ALT =
        "C:/Users/Dell/OneDrive/Documentos/teste_dani/teste_bia_dani (1).pcap";

    localparam string RESULT_FILE =
    "C:/Users/Dell/OneDrive/Documentos/teste_dani/resultado_simulacao.txt";

    localparam integer MAX_PACKETS = 10000;
    localparam integer MAX_FRAME_BYTES = 65536;
    localparam integer CLOCK_PERIOD_NS = 10;
    localparam integer DLT_EN10MB = 1;

    // Reduz a escala temporal para a simulacao.
    // O timestamp aplicado ao TSU continua representando o instante
    // original do PCAP.
    localparam integer PCAP_REPLAY_SCALE = 1000000;

    logic rx_clk;
    logic rx_axis_aresetn;

    logic [63:0] rx_axis_tdata;
    logic [7:0]  rx_axis_tkeep;
    logic        rx_axis_tvalid;
    logic        rx_axis_tlast;
    logic        rx_axis_tuser;

    logic [79:0] tsu_timestamp;

    logic        packet_done;
    logic        packet_error;
    logic [31:0] packet_id;
    logic [31:0] packet_byte_count;
    logic [31:0] packet_word_count;
    logic [79:0] packet_timestamp;

    integer pcap_fd;
    integer result_fd;

    string pcap_file_used;

    integer error_count;
    integer total_words;
    integer observed_packets;
    integer pcap_packet_count;

    integer current_expected_bytes;
    integer current_expected_words;

    integer i;
    integer byte_ok;
    integer record_complete;
    integer frame_complete;
    integer pcap_done;

    integer included_length;
    integer original_length;
    integer pcap_snaplen;
    integer pcap_link_type;

    logic [31:0] record_timestamp_seconds;
    logic [31:0] record_timestamp_fraction;

    logic [79:0] timestamp_for_record;
    logic [79:0] expected_first_timestamp;

    logic [7:0] global_header [0:23];
    logic [7:0] record_header [0:15];
    logic [7:0] frame_bytes [0:MAX_FRAME_BYTES-1];

    logic pcap_little_endian;
    logic pcap_fraction_is_ns;
    logic global_header_ok;

    longint unsigned previous_timestamp_total_ns;

    // ============================================================
    // CLOCK
    // ============================================================

    always #(CLOCK_PERIOD_NS / 2)
        rx_clk = ~rx_clk;

    // ============================================================
    // DUT MOCKUP
    // ============================================================

    mac_rx_mockup dut (
        .rx_clk             (rx_clk),
        .rx_axis_aresetn    (rx_axis_aresetn),

        .rx_axis_tdata      (rx_axis_tdata),
        .rx_axis_tkeep      (rx_axis_tkeep),
        .rx_axis_tvalid     (rx_axis_tvalid),
        .rx_axis_tlast      (rx_axis_tlast),
        .rx_axis_tuser      (rx_axis_tuser),

        .tsu_timestamp      (tsu_timestamp),

        .packet_done        (packet_done),
        .packet_error       (packet_error),
        .packet_id          (packet_id),
        .packet_byte_count  (packet_byte_count),
        .packet_word_count  (packet_word_count),
        .packet_timestamp   (packet_timestamp)
    );

    // ============================================================
    // DECODIFICA UM INTEIRO DE 32 BITS
    // ============================================================

    function automatic [31:0] decode_u32(
        input logic [7:0] b0,
        input logic [7:0] b1,
        input logic [7:0] b2,
        input logic [7:0] b3,
        input logic       little_endian
    );
        begin
            if (little_endian)
                decode_u32 = {b3, b2, b1, b0};
            else
                decode_u32 = {b0, b1, b2, b3};
        end
    endfunction

    // ============================================================
    // CONTAGEM DE BYTES VALIDOS
    // ============================================================

    function automatic integer count_keep(
        input logic [7:0] keep
    );
        integer index;
        begin
            count_keep = 0;

            for (index = 0; index < 8; index = index + 1)
                count_keep = count_keep + keep[index];
        end
    endfunction

    // ============================================================
    // VALIDACAO DO TKEEP
    // ============================================================

    function automatic logic valid_keep(
        input logic [7:0] keep
    );
        begin
            case (keep)
                8'h01, 8'h03, 8'h07, 8'h0F,
                8'h1F, 8'h3F, 8'h7F, 8'hFF:
                    valid_keep = 1'b1;

                default:
                    valid_keep = 1'b0;
            endcase
        end
    endfunction

    // ============================================================
    // CALCULA TKEEP A PARTIR DOS BYTES VALIDOS
    // ============================================================

    function automatic [7:0] keep_from_bytes(
        input integer byte_count
    );
        begin
            case (byte_count)
                1: keep_from_bytes = 8'h01;
                2: keep_from_bytes = 8'h03;
                3: keep_from_bytes = 8'h07;
                4: keep_from_bytes = 8'h0F;
                5: keep_from_bytes = 8'h1F;
                6: keep_from_bytes = 8'h3F;
                7: keep_from_bytes = 8'h7F;
                8: keep_from_bytes = 8'hFF;

                default:
                    keep_from_bytes = 8'h00;
            endcase
        end
    endfunction

    // ============================================================
    // CONVERTE TIMESTAMP DE 80 BITS PARA NANOSSEGUNDOS TOTAIS
    // ============================================================

    function automatic longint unsigned timestamp80_to_total_ns(
        input logic [79:0] timestamp_i
    );
        longint unsigned seconds_value;
        begin
            seconds_value = timestamp_i[79:32];

            timestamp80_to_total_ns =
                seconds_value * 64'd1000000000
                + timestamp_i[31:0];
        end
    endfunction

    // ============================================================
    // COLOCA AXI-STREAM EM ESTADO OCIOSO
    // ============================================================

    task automatic drive_idle;
        begin
            rx_axis_tdata  = 64'd0;
            rx_axis_tkeep  = 8'd0;
            rx_axis_tvalid = 1'b0;
            rx_axis_tlast  = 1'b0;
            rx_axis_tuser  = 1'b0;
        end
    endtask

    // ============================================================
    // LE UM BYTE DO ARQUIVO PCAP
    // ============================================================

    task automatic read_pcap_byte(
        output logic [7:0] value,
        output integer     ok
    );
        integer character_value;
        begin
            character_value = $fgetc(pcap_fd);

            if (character_value < 0) begin
                value = 8'd0;
                ok = 0;
            end
            else begin
                value = character_value[7:0];
                ok = 1;
            end
        end
    endtask

    // ============================================================
    // LE O CABECALHO GLOBAL PCAP
    // ============================================================

    task automatic read_global_pcap_header;
        reg [31:0] magic;
        begin
            global_header_ok = 1'b1;

            for (i = 0; i < 24; i = i + 1) begin
                read_pcap_byte(global_header[i], byte_ok);

                if (!byte_ok)
                    global_header_ok = 1'b0;
            end

            if (global_header_ok) begin
                magic = {
                    global_header[0],
                    global_header[1],
                    global_header[2],
                    global_header[3]
                };

                case (magic)

                    // PCAP little-endian, microssegundos
                    32'hD4C3B2A1: begin
                        pcap_little_endian = 1'b1;
                        pcap_fraction_is_ns = 1'b0;
                    end

                    // PCAP little-endian, nanossegundos
                    32'h4D3CB2A1: begin
                        pcap_little_endian = 1'b1;
                        pcap_fraction_is_ns = 1'b1;
                    end

                    // PCAP big-endian, microssegundos
                    32'hA1B2C3D4: begin
                        pcap_little_endian = 1'b0;
                        pcap_fraction_is_ns = 1'b0;
                    end

                    // PCAP big-endian, nanossegundos
                    32'hA1B23C4D: begin
                        pcap_little_endian = 1'b0;
                        pcap_fraction_is_ns = 1'b1;
                    end

                    default: begin
                        global_header_ok = 1'b0;
                    end
                endcase

                if (global_header_ok) begin

                    pcap_snaplen = decode_u32(
                        global_header[16],
                        global_header[17],
                        global_header[18],
                        global_header[19],
                        pcap_little_endian
                    );

                    pcap_link_type = decode_u32(
                        global_header[20],
                        global_header[21],
                        global_header[22],
                        global_header[23],
                        pcap_little_endian
                    );

                    if (pcap_link_type != DLT_EN10MB) begin
                        global_header_ok = 1'b0;

                        $display(
                            "ERRO: link-type %0d nao suportado; esperado DLT_EN10MB=1.",
                            pcap_link_type
                        );
                    end
                end
            end
        end
    endtask

    // ============================================================
    // CONVERTE TIMESTAMP PCAP PARA 80 BITS
    //
    // [79:32] = segundos
    // [31:0]  = nanossegundos
    // ============================================================

    task automatic make_timestamp80(
        input  logic [31:0] seconds_i,
        input  logic [31:0] fraction_i,
        output logic [79:0] timestamp_o
    );
        longint unsigned fraction_wide;
        longint unsigned nanoseconds_part;

        begin
            fraction_wide = fraction_i;

            if (pcap_fraction_is_ns)
                nanoseconds_part = fraction_wide;
            else
                nanoseconds_part = fraction_wide * 64'd1000;

            if (nanoseconds_part > 64'd999999999) begin
                $display(
                    "ERRO: fracao do timestamp excede 999999999 ns."
                );

                error_count = error_count + 1;
            end

            timestamp_o = {
                16'd0,
                seconds_i,
                nanoseconds_part[31:0]
            };
        end
    endtask

    // ============================================================
    // REPRODUZ INTERVALO ENTRE PACOTES
    // ============================================================

    task automatic wait_pcap_interval(
        input logic [79:0] current_timestamp,
        input integer      packet_number
    );
        longint unsigned current_total_ns;
        longint unsigned gap_total_ns;
        longint unsigned simulation_gap_ns;

        integer gap_cycles;
        integer cycle_index;

        begin
            current_total_ns =
                timestamp80_to_total_ns(current_timestamp);

            if (packet_number > 1) begin

                if (current_total_ns < previous_timestamp_total_ns) begin
                    $display(
                        "ERRO: timestamp fora de ordem no pacote %0d.",
                        packet_number
                    );

                    error_count = error_count + 1;
                    gap_total_ns = 0;
                end
                else begin
                    gap_total_ns =
                        current_total_ns - previous_timestamp_total_ns;
                end

                simulation_gap_ns =
                    gap_total_ns / PCAP_REPLAY_SCALE;

                gap_cycles =
                    (simulation_gap_ns + CLOCK_PERIOD_NS - 1)
                    / CLOCK_PERIOD_NS;

                if (gap_cycles < 1)
                    gap_cycles = 1;

                for (cycle_index = 0;
                     cycle_index < gap_cycles;
                     cycle_index = cycle_index + 1) begin

                    @(negedge rx_clk);
                    drive_idle();

                    @(posedge rx_clk);
                    #1ps;
                end
            end

            previous_timestamp_total_ns = current_total_ns;
        end
    endtask

    // ============================================================
    // ENVIA O PACOTE PARA A INTERFACE AXI-STREAM
    // ============================================================

    task automatic send_packet_from_pcap(
        input integer      frame_length,
        input logic [79:0] packet_timestamp_i,
        input integer      packet_number,
        input logic [31:0] pcap_seconds_i,
        input logic [31:0] pcap_fraction_i
    );

        integer word_total;
        integer word_index;
        integer start_index;
        integer valid_bytes;
        integer byte_index;

        logic [63:0] data_word;
        logic [7:0] keep_word;
        logic last_word;

        begin
            if (frame_length <= 0) begin
                $display(
                    "ERRO: pacote %0d possui tamanho invalido.",
                    packet_number
                );

                error_count = error_count + 1;
            end
            else begin
                word_total = (frame_length + 7) / 8;

                current_expected_bytes = frame_length;
                current_expected_words = word_total;
                expected_first_timestamp = packet_timestamp_i;

                wait_pcap_interval(
                    packet_timestamp_i,
                    packet_number
                );

                for (word_index = 0;
                     word_index < word_total;
                     word_index = word_index + 1) begin

                    @(negedge rx_clk);

                    // Timestamp aplicado antes do primeiro beat.
                    if (word_index == 0)
                        tsu_timestamp = packet_timestamp_i;

                    start_index = word_index * 8;

                    valid_bytes = frame_length - start_index;

                    if (valid_bytes > 8)
                        valid_bytes = 8;

                    data_word = 64'd0;

                    for (byte_index = 0;
                         byte_index < valid_bytes;
                         byte_index = byte_index + 1) begin

                        data_word[byte_index * 8 +: 8] =
                            frame_bytes[start_index + byte_index];
                    end

                    keep_word = keep_from_bytes(valid_bytes);

                    last_word =
                        (word_index == word_total - 1);

                    rx_axis_tdata  = data_word;
                    rx_axis_tkeep  = keep_word;
                    rx_axis_tvalid = 1'b1;
                    rx_axis_tlast  = last_word;
                    rx_axis_tuser  = last_word;

                    if (!valid_keep(keep_word)) begin
                        $display(
                            "ERRO: TKEEP invalido no pacote %0d word %0d: %02h",
                            packet_number,
                            word_index,
                            keep_word
                        );

                        error_count = error_count + 1;
                    end

                    total_words = total_words + 1;

                    $display(
                        "pcap=%0d word=%0d pcap_sec=%0d pcap_frac=%0d tsu80=%020h ts_sec=%0d ts_ns=%0d tdata=%016h tkeep=%02h tvalid=1 tlast=%0d tuser=%0d",
                        packet_number,
                        word_index,
                        pcap_seconds_i,
                        pcap_fraction_i,
                        tsu_timestamp,
                        tsu_timestamp[79:32],
                        tsu_timestamp[31:0],
                        data_word,
                        keep_word,
                        last_word,
                        last_word
                    );

                    $fdisplay(
                        result_fd,
                        "pcap=%0d word=%0d pcap_sec=%0d pcap_frac=%0d tsu80=%020h ts_sec=%0d ts_ns=%0d tdata=%016h tkeep=%02h tvalid=1 tlast=%0d tuser=%0d",
                        packet_number,
                        word_index,
                        pcap_seconds_i,
                        pcap_fraction_i,
                        tsu_timestamp,
                        tsu_timestamp[79:32],
                        tsu_timestamp[31:0],
                        data_word,
                        keep_word,
                        last_word,
                        last_word
                    );

                    @(posedge rx_clk);
                    #1ps;

                    if (packet_done) begin

                        if (!last_word) begin
                            $display(
                                "ERRO: DUT encerrou pacote %0d antes do TLAST.",
                                packet_number
                            );

                            error_count = error_count + 1;
                        end

                        observed_packets = observed_packets + 1;

                        $display(
                            "Pacote %0d concluido: bytes=%0d/%0d words=%0d/%0d timestamp=%020h/%020h erro=%0d",
                            packet_number,
                            packet_byte_count,
                            current_expected_bytes,
                            packet_word_count,
                            current_expected_words,
                            packet_timestamp,
                            expected_first_timestamp,
                            packet_error
                        );

                        $fdisplay(
                            result_fd,
                            "Pacote %0d concluido: bytes=%0d/%0d words=%0d/%0d timestamp=%020h/%020h erro=%0d",
                            packet_number,
                            packet_byte_count,
                            current_expected_bytes,
                            packet_word_count,
                            current_expected_words,
                            packet_timestamp,
                            expected_first_timestamp,
                            packet_error
                        );

                        if (packet_error !== 1'b0)
                            error_count = error_count + 1;

                        if (packet_id !== packet_number)
                            error_count = error_count + 1;

                        if (packet_byte_count !== current_expected_bytes)
                            error_count = error_count + 1;

                        if (packet_word_count !== current_expected_words)
                            error_count = error_count + 1;

                        if (packet_timestamp !== expected_first_timestamp)
                            error_count = error_count + 1;
                    end
                    else if (last_word) begin
                        $display(
                            "ERRO: TLAST foi enviado, mas o DUT nao concluiu o pacote %0d.",
                            packet_number
                        );

                        error_count = error_count + 1;
                    end

                    rx_axis_tvalid = 1'b0;
                    rx_axis_tlast  = 1'b0;
                    rx_axis_tuser  = 1'b0;
                end
            end
        end
    endtask

    // ============================================================
    // PROCESSO PRINCIPAL
    // ============================================================

    initial begin

        rx_clk          = 1'b0;
        rx_axis_aresetn = 1'b0;

        rx_axis_tdata  = 64'd0;
        rx_axis_tkeep  = 8'd0;
        rx_axis_tvalid = 1'b0;
        rx_axis_tlast  = 1'b0;
        rx_axis_tuser  = 1'b0;

        tsu_timestamp = 80'd0;

        error_count = 0;
        total_words = 0;
        observed_packets = 0;
        pcap_packet_count = 0;

        current_expected_bytes = 0;
        current_expected_words = 0;

        previous_timestamp_total_ns = 0;

        // Reset
        repeat (5)
            @(posedge rx_clk);

        if (packet_done !== 1'b0 || packet_id !== 0) begin
            $display(
                "ERRO: DUT nao permaneceu limpo durante o reset."
            );

            error_count = error_count + 1;
        end

        @(negedge rx_clk);
        rx_axis_aresetn = 1'b1;

        // --------------------------------------------------------
        // ABERTURA DO PCAP
        // --------------------------------------------------------

        pcap_file_used = PCAP_FILE;
        pcap_fd = $fopen(pcap_file_used, "rb");

        if (pcap_fd == 0) begin
            pcap_file_used = PCAP_FILE_RELATIVE_ALT;
            pcap_fd = $fopen(pcap_file_used, "rb");
        end

        if (pcap_fd == 0) begin
            pcap_file_used = PCAP_FILE_ABSOLUTE;
            pcap_fd = $fopen(pcap_file_used, "rb");
        end

        if (pcap_fd == 0) begin
            pcap_file_used = PCAP_FILE_ABSOLUTE_ALT;
            pcap_fd = $fopen(pcap_file_used, "rb");
        end

        if (pcap_fd == 0) begin
            $display("ERRO: nao foi possivel abrir o PCAP.");

            $display(
                "Verifique os caminhos configurados no inicio da testbench."
            );

            $display("Caminho principal: %s", PCAP_FILE_ABSOLUTE);

            $fatal(1, "PCAP nao encontrado; simulacao interrompida.");
        end

        $display(
            "PCAP aberto com sucesso: %s",
            pcap_file_used
        );

        // --------------------------------------------------------
        // ABERTURA DO RELATORIO
        // --------------------------------------------------------

        result_fd = $fopen(RESULT_FILE, "w");

        if (result_fd == 0) begin
            $display(
                "ERRO: nao foi possivel criar %s.",
                RESULT_FILE
            );

            $fclose(pcap_fd);

            $fatal(
                1,
                "Nao foi possivel criar o relatorio da simulacao."
            );
        end

        $fdisplay(
            result_fd,
            "# Resultado da simulacao do MAC RX mockup"
        );

        $fdisplay(
            result_fd,
            "# Entrada direta: %s",
            pcap_file_used
        );

        $fdisplay(
            result_fd,
            "# Timestamp IEEE 1588 ToD: 80 bits = Seconds[79:32] + Nanoseconds[31:0]"
        );

        $fdisplay(
            result_fd,
            "# Campos: pacote word pcap_sec pcap_frac tsu80 tdata tkeep tvalid tlast tuser"
        );

        $fdisplay(result_fd, "");

        // --------------------------------------------------------
        // LEITURA DO CABECALHO GLOBAL
        // --------------------------------------------------------

        read_global_pcap_header();

        if (!global_header_ok) begin
            $display(
                "ERRO: cabecalho global PCAP invalido ou incompativel."
            );

            error_count = error_count + 1;
        end
        else begin

            $display(
                "PCAP aberto: link-type=DLT_EN10MB, fracao=%s",
                pcap_fraction_is_ns
                    ? "nanosegundos"
                    : "microsegundos"
            );

            pcap_done = 1'b0;

            // ----------------------------------------------------
            // LEITURA DOS REGISTROS
            // ----------------------------------------------------

            while (!pcap_done) begin

                record_complete = 1'b1;

                for (i = 0; i < 16; i = i + 1) begin
                    read_pcap_byte(record_header[i], byte_ok);

                    if (!byte_ok)
                        record_complete = 1'b0;
                end

                if (!record_complete) begin
                    // EOF ou cabecalho de registro incompleto.
                    pcap_done = 1'b1;
                end
                else begin

                    record_timestamp_seconds = decode_u32(
                        record_header[0],
                        record_header[1],
                        record_header[2],
                        record_header[3],
                        pcap_little_endian
                    );

                    record_timestamp_fraction = decode_u32(
                        record_header[4],
                        record_header[5],
                        record_header[6],
                        record_header[7],
                        pcap_little_endian
                    );

                    included_length = decode_u32(
                        record_header[8],
                        record_header[9],
                        record_header[10],
                        record_header[11],
                        pcap_little_endian
                    );

                    original_length = decode_u32(
                        record_header[12],
                        record_header[13],
                        record_header[14],
                        record_header[15],
                        pcap_little_endian
                    );

                    if (included_length <= 0) begin
                        $display(
                            "ERRO: registro PCAP com tamanho invalido."
                        );

                        error_count = error_count + 1;
                        pcap_done = 1'b1;
                    end
                    else if (included_length > MAX_FRAME_BYTES) begin

                        $display(
                            "ERRO: pacote de %0d bytes excede MAX_FRAME_BYTES=%0d.",
                            included_length,
                            MAX_FRAME_BYTES
                        );

                        error_count = error_count + 1;
                        pcap_done = 1'b1;
                    end
                    else if (pcap_packet_count >= MAX_PACKETS) begin

                        $display(
                            "ERRO: MAX_PACKETS insuficiente."
                        );

                        error_count = error_count + 1;
                        pcap_done = 1'b1;
                    end
                    else begin

                        frame_complete = 1'b1;

                        for (i = 0; i < included_length; i = i + 1) begin
                            read_pcap_byte(frame_bytes[i], byte_ok);

                            if (!byte_ok)
                                frame_complete = 1'b0;
                        end

                        if (!frame_complete) begin

                            $display(
                                "ERRO: PCAP truncado durante a leitura do pacote."
                            );

                            error_count = error_count + 1;
                            pcap_done = 1'b1;
                        end
                        else begin

                            pcap_packet_count =
                                pcap_packet_count + 1;

                            make_timestamp80(
                                record_timestamp_seconds,
                                record_timestamp_fraction,
                                timestamp_for_record
                            );

                            send_packet_from_pcap(
                                included_length,
                                timestamp_for_record,
                                pcap_packet_count,
                                record_timestamp_seconds,
                                record_timestamp_fraction
                            );
                        end
                    end
                end
            end
        end

        // --------------------------------------------------------
        // FINALIZACAO
        // --------------------------------------------------------

        $fclose(pcap_fd);

        if (pcap_packet_count == 0) begin
            $display(
                "ERRO: nenhum pacote foi lido do PCAP."
            );

            error_count = error_count + 1;
        end

        if (observed_packets != pcap_packet_count) begin
            $display(
                "ERRO: pacotes observados=%0d, lidos=%0d.",
                observed_packets,
                pcap_packet_count
            );

            error_count = error_count + 1;
        end

        @(negedge rx_clk);
        drive_idle();

        repeat (3)
            @(posedge rx_clk);

        if (error_count == 0) begin

            $display("===============================================");

            $display(
                "TESTE PASSOU: PCAP direto, clock, reset, TKEEP, TLAST e timestamp 80 bits."
            );

            $display(
                "Pacotes processados: %0d",
                pcap_packet_count
            );

            $display(
                "Palavras processadas: %0d",
                total_words
            );

            $display("===============================================");

            $fdisplay(
                result_fd,
                "==============================================="
            );

            $fdisplay(
                result_fd,
                "TESTE PASSOU: PCAP direto, clock, reset, TKEEP, TLAST e timestamp 80 bits."
            );

            $fdisplay(
                result_fd,
                "Pacotes processados: %0d",
                pcap_packet_count
            );

            $fdisplay(
                result_fd,
                "Palavras processadas: %0d",
                total_words
            );

            $fdisplay(
                result_fd,
                "==============================================="
            );
        end
        else begin

            $display(
                "TESTE FALHOU: %0d erro(s).",
                error_count
            );

            $fdisplay(
                result_fd,
                "TESTE FALHOU: %0d erro(s).",
                error_count
            );
        end

        $fclose(result_fd);

        $finish;
    end

endmodule
