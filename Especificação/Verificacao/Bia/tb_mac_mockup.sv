`timescale 1ns/1ps

// Testbench do DUT mockup.
// O arquivo pode conter quatro campos:
//   tdata tkeep tvalid tlast
// ou cinco campos, com tuser.
// O quinto campo e aplicado na interface do DUT. Para quadro valido,
// tuser deve ser 1 no beat com tlast; antes disso ele pode ser 0.
module tb_mac_mockup;

    localparam string STREAM_FILE      = "stream_words.txt";
    localparam string RESULT_FILE      = "resultado_simulacao.txt";
    localparam integer MAX_PACKETS     = 10000;
    localparam integer CLOCK_PERIOD_NS = 10;

    logic        rx_clk;
    logic        rx_axis_aresetn;
    logic [63:0] rx_axis_tdata;
    logic  [7:0] rx_axis_tkeep;
    logic        rx_axis_tvalid;
    logic        rx_axis_tlast;
    logic        rx_axis_tuser;
    logic [63:0] tsu_timestamp_ns;

    logic        packet_done;
    logic        packet_error;
    logic [31:0] packet_id;
    logic [31:0] packet_byte_count;
    logic [31:0] packet_word_count;
    logic [63:0] packet_timestamp_ns;

    integer stream_fd;
    integer result_fd;
    integer rc;
    integer error_count;
    integer total_words;
    integer packet_index;
    integer observed_packets;
    integer current_expected_bytes;
    integer current_expected_words;
    integer word_index;

    integer valid_i;
    integer last_i;
    integer user_i;

    logic [63:0] data_i;
    logic  [7:0] keep_i;

    // O Icarus exige que o primeiro argumento de $fgets seja um reg.
    reg [4095:0] line;

    longint unsigned expected_first_timestamp;
    bit first_word_of_packet;

    // Clock de 10 ns
    always #(CLOCK_PERIOD_NS / 2) rx_clk = ~rx_clk;

    // TSU:
    // inicia em zero durante o reset
    // e avanca 10 ns a cada ciclo de clock.
    always_ff @(posedge rx_clk or negedge rx_axis_aresetn) begin
        if (!rx_axis_aresetn)
            tsu_timestamp_ns <= 64'd0;
        else
            tsu_timestamp_ns <= tsu_timestamp_ns + CLOCK_PERIOD_NS;
    end

    // Instancia o DUT mockup
    mac_rx_mockup dut (
        .rx_clk              (rx_clk),
        .rx_axis_aresetn     (rx_axis_aresetn),
        .rx_axis_tdata       (rx_axis_tdata),
        .rx_axis_tkeep       (rx_axis_tkeep),
        .rx_axis_tvalid      (rx_axis_tvalid),
        .rx_axis_tlast       (rx_axis_tlast),
        .rx_axis_tuser       (rx_axis_tuser),
        .tsu_timestamp_ns    (tsu_timestamp_ns),
        .packet_done         (packet_done),
        .packet_error        (packet_error),
        .packet_id           (packet_id),
        .packet_byte_count   (packet_byte_count),
        .packet_word_count   (packet_word_count),
        .packet_timestamp_ns (packet_timestamp_ns)
    );

    // Conta os bits 1 de TKEEP
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

    // Verifica se TKEEP possui formato valido
    function automatic logic valid_keep(
        input logic [7:0] keep
    );
        begin
            case (keep)
                8'h01,
                8'h03,
                8'h07,
                8'h0F,
                8'h1F,
                8'h3F,
                8'h7F,
                8'hFF:
                    valid_keep = 1'b1;

                default:
                    valid_keep = 1'b0;
            endcase
        end
    endfunction

    // Coloca a interface em estado ocioso
    task automatic drive_idle;
        begin
            rx_axis_tdata  = 64'd0;
            rx_axis_tkeep  = 8'd0;
            rx_axis_tvalid = 1'b0;
            rx_axis_tlast  = 1'b0;
            rx_axis_tuser  = 1'b0;
        end
    endtask

    initial begin

        // Inicializacao dos sinais
        rx_clk          = 1'b0;
        rx_axis_aresetn = 1'b0;

        rx_axis_tdata  = 64'd0;
        rx_axis_tkeep  = 8'd0;
        rx_axis_tvalid = 1'b0;
        rx_axis_tlast  = 1'b0;
        rx_axis_tuser  = 1'b0;

        error_count             = 0;
        total_words             = 0;
        packet_index            = 0;
        observed_packets        = 0;
        current_expected_bytes  = 0;
        current_expected_words  = 0;
        word_index              = 0;

        first_word_of_packet     = 1'b1;
        expected_first_timestamp = 64'd0;

        // Mantem o DUT em reset durante cinco ciclos
        repeat (5) @(posedge rx_clk);

        // Verifica se o DUT permaneceu limpo durante o reset
        if (packet_done !== 1'b0 || packet_id !== 0) begin
            $display("ERRO: DUT nao permaneceu limpo durante o reset.");
            error_count = error_count + 1;
        end

        // Retira o reset em uma borda de descida
        @(negedge rx_clk);
        rx_axis_aresetn = 1'b1;

        // Abre o arquivo de estimulos
        stream_fd = $fopen(STREAM_FILE, "r");

        if (stream_fd == 0) begin
            $display(
                "ERRO: nao foi possivel abrir %s.",
                STREAM_FILE
            );
            $finish;
        end

        // Cria o arquivo de resultado
        result_fd = $fopen(RESULT_FILE, "w");

        if (result_fd == 0) begin
            $display(
                "ERRO: nao foi possivel criar %s.",
                RESULT_FILE
            );

            $fclose(stream_fd);
            $finish;
        end

        // Cabecalho do arquivo de resultado
        $fdisplay(
            result_fd,
            "# Resultado da simulacao do MAC RX mockup"
        );

        $fdisplay(
            result_fd,
            "# Campos: pacote word tsu_ns tdata tkeep tvalid tlast tuser"
        );

        $fdisplay(result_fd, "");

        // Le cada linha do stream_words.txt
        while ($fgets(line, stream_fd) != 0) begin

            // Le:
            // tdata tkeep tvalid tlast tuser
            rc = $sscanf(
                line,
                "%h %h %d %d %d",
                data_i,
                keep_i,
                valid_i,
                last_i,
                user_i
            );

            // Se o arquivo possuir apenas quatro campos,
            // TUSER sera inferido a partir de TLAST.
            if (rc == 4)
                user_i = last_i;

            // Ignora cabecalho e comentarios
            if (rc == 4 || rc == 5) begin

                // Detecta o primeiro beat de um novo pacote
                if (first_word_of_packet && valid_i != 0) begin

                    if (packet_index >= MAX_PACKETS) begin
                        $display(
                            "ERRO: MAX_PACKETS insuficiente."
                        );

                        error_count = error_count + 1;
                        $finish;
                    end

                    // Insere um ciclo ocioso entre pacotes
                    if (packet_index > 0) begin
                        @(negedge rx_clk);
                        drive_idle();

                        @(posedge rx_clk);
                        #1ps;
                    end

                    // O DUT captura este timestamp
                    // no proximo posedge.
                    @(negedge rx_clk);

                    expected_first_timestamp = tsu_timestamp_ns;
                    current_expected_bytes   = 0;
                    current_expected_words   = 0;
                    word_index               = 0;

                end else begin
                    @(negedge rx_clk);
                end

                // Atualiza contadores esperados
                if (valid_i != 0) begin

                    current_expected_bytes =
                        current_expected_bytes + count_keep(keep_i);

                    current_expected_words =
                        current_expected_words + 1;

                    total_words = total_words + 1;

                    // Verifica TKEEP
                    if (!valid_keep(keep_i)) begin
                        $display(
                            "ERRO: TKEEP invalido no pacote %0d, word %0d: %02h",
                            packet_index + 1,
                            word_index,
                            keep_i
                        );

                        error_count = error_count + 1;
                    end
                end

                // TUSER e verificado no encerramento do pacote
                if (valid_i != 0 &&
                    last_i  != 0 &&
                    user_i  != 1) begin

                    $display(
                        "ERRO: TUSER=0 no encerramento do pacote %0d.",
                        packet_index + 1
                    );

                    error_count = error_count + 1;
                end

                // Aplica os sinais ao DUT
                rx_axis_tdata  = data_i;
                rx_axis_tkeep  = keep_i;
                rx_axis_tvalid = (valid_i != 0);
                rx_axis_tlast  = (last_i != 0);
                rx_axis_tuser  = (user_i != 0);

                // Mostra no terminal
                $display(
                    "pacote=%0d word=%0d tsu=%0d ns tdata=%016h tkeep=%02h tvalid=%0d tlast=%0d tuser=%0d",
                    packet_index + 1,
                    word_index,
                    tsu_timestamp_ns,
                    data_i,
                    keep_i,
                    valid_i,
                    last_i,
                    user_i
                );

                // Grava no arquivo TXT
                $fdisplay(
                    result_fd,
                    "pacote=%0d word=%0d tsu=%0d ns tdata=%016h tkeep=%02h tvalid=%0d tlast=%0d tuser=%0d",
                    packet_index + 1,
                    word_index,
                    tsu_timestamp_ns,
                    data_i,
                    keep_i,
                    valid_i,
                    last_i,
                    user_i
                );

                // O DUT amostra na borda de subida
                @(posedge rx_clk);
                #1ps;

                // Verifica se o pacote foi concluido
                if (packet_done) begin

                    observed_packets = observed_packets + 1;

                    // Mostra no terminal
                    $display(
                        "Pacote %0d concluido: bytes=%0d/%0d words=%0d/%0d timestamp=%0d/%0d ns erro=%0d",
                        observed_packets,
                        packet_byte_count,
                        current_expected_bytes,
                        packet_word_count,
                        current_expected_words,
                        packet_timestamp_ns,
                        expected_first_timestamp,
                        packet_error
                    );

                    // Grava no arquivo TXT
                    $fdisplay(
                        result_fd,
                        "Pacote %0d concluido: bytes=%0d/%0d words=%0d/%0d timestamp=%0d/%0d ns erro=%0d",
                        observed_packets,
                        packet_byte_count,
                        current_expected_bytes,
                        packet_word_count,
                        current_expected_words,
                        packet_timestamp_ns,
                        expected_first_timestamp,
                        packet_error
                    );

                    // Verificacoes do pacote
                    if (!last_i) begin
                        $display(
                            "ERRO: DUT concluiu sem TLAST no estimulo."
                        );

                        error_count = error_count + 1;
                    end

                    if (packet_error)
                        error_count = error_count + 1;

                    if (packet_id != observed_packets)
                        error_count = error_count + 1;

                    if (packet_byte_count != current_expected_bytes)
                        error_count = error_count + 1;

                    if (packet_word_count != current_expected_words)
                        error_count = error_count + 1;

                    if (packet_timestamp_ns != expected_first_timestamp)
                        error_count = error_count + 1;

                end else if (last_i) begin

                    $display(
                        "ERRO: TLAST foi enviado, mas o DUT nao concluiu o pacote."
                    );

                    error_count = error_count + 1;
                end

                // Atualiza o controle de pacote
                if (last_i != 0) begin
                    packet_index         = packet_index + 1;
                    first_word_of_packet = 1'b1;
                    word_index           = 0;

                end else if (valid_i != 0) begin
                    first_word_of_packet = 1'b0;
                    word_index           = word_index + 1;
                end

                // Retorna os sinais para o estado ocioso
                rx_axis_tvalid = 1'b0;
                rx_axis_tlast  = 1'b0;
                rx_axis_tuser  = 1'b0;
            end
        end

        // Fecha o arquivo de entrada
        $fclose(stream_fd);

        // Verifica se o ultimo pacote terminou com TLAST
        if (!first_word_of_packet) begin
            $display(
                "ERRO: arquivo terminou sem TLAST no ultimo pacote."
            );

            error_count = error_count + 1;
        end

        // Mantem a interface ociosa por mais alguns ciclos
        @(negedge rx_clk);
        drive_idle();

        repeat (3) @(posedge rx_clk);

        // Verifica a quantidade de pacotes
        if (observed_packets != packet_index) begin
            $display(
                "ERRO: pacotes observados=%0d, esperados=%0d.",
                observed_packets,
                packet_index
            );

            error_count = error_count + 1;
        end

        // Resultado final
        if (error_count == 0) begin

            $display(
                "==============================================="
            );

            $display(
                "TESTE PASSOU: clock, reset, TKEEP, TLAST e TSU."
            );

            $display(
                "Pacotes processados: %0d",
                packet_index
            );

            $display(
                "Palavras processadas: %0d",
                total_words
            );

            $display(
                "==============================================="
            );

            $fdisplay(
                result_fd,
                "==============================================="
            );

            $fdisplay(
                result_fd,
                "TESTE PASSOU: clock, reset, TKEEP, TLAST e TSU."
            );

            $fdisplay(
                result_fd,
                "Pacotes processados: %0d",
                packet_index
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

        end else begin

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

        // Fecha o arquivo de resultado
        $fclose(result_fd);

        $finish;
    end

endmodule