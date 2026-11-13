`timescale 1ns/1ps
`default_nettype none

// ============================================================================
// Campanha ponta a ponta com PCAP grande (DLT_NULL / loopback)
//
// Caminho:
//   PCAP -> AXI Stream -> Parser -> FIU -> Hash -> Controller
//        -> Flow Table -> Flow Finalizer -> CSV
//
// Primeira campanha conservadora:
//   - processa os PRIMEIROS 10.000 registros do PCAP, para comparar com
//     a campanha anterior do Parser (7.418 pacotes validos observados);
//   - L3_OFFSET = 4, pois o PCAP usa DLT_NULL;
//   - timestamp[79:32] = seconds;
//   - timestamp[31:0]  = nanoseconds;
//   - TUSER = 1 para os quadros do PCAP;
//   - 80 clocks de folga apos cada quadro, mantendo a condicao usada pela
//     frente de Features na validacao funcional;
//   - ao final, pcap_done dispara a varredura completa da Flow Table;
//   - cada feature gerada e salva em features_pcap_grande.csv.
//
// OBS.: este teste valida estabilidade/integração em volume. A campanha de
// throughput sem folga deve ser feita separadamente.
// ============================================================================
module tb_pcap_grande_ponta_a_ponta;

    localparam string PCAP_FILE = "teste.pcap";
    localparam string CSV_FILE  = "features_pcap_grande.csv";

    localparam int MAX_RECORDS = 10000;
    localparam int GAP_CLOCKS  = 80;
    localparam int SCAN_ENTRIES_TB = 65536;

    // Timeout grande para acomodar 10k pacotes + varredura de 65.536 entradas.
    localparam int MAX_FINAL_WAIT_CYCLES = 3000000;

    logic clk;
    logic reset;

    logic [63:0] TDATA;
    logic [7:0]  TKEEP;
    logic        TVALID;
    logic        TLAST;
    logic        TUSER;
    logic [79:0] timestamp_in;
    logic        pcap_done;

    logic [247:0] feature_vector;
    logic         fin_done;

    logic [7:0] frame [0:65535];

    integer fd;
    integer csv_fd;
    integer c;
    integer i;
    integer pkt_idx;
    integer records_sent;
    integer parser_valid_count;
    integer lookup_count;
    integer miss_count;
    integer hit_count;
    integer collision_count_observed;
    integer feature_count;
    integer wait_cycles;
    integer errors;

    longint unsigned ts_sec;
    longint unsigned ts_usec;
    longint unsigned incl_len;
    longint unsigned orig_len;

    logic [31:0] ns_part;
    logic [79:0] timestamp_tod;

    logic [103:0] feature_key;
    logic [31:0]  feature_packets;
    logic [31:0]  feature_bytes;
    logic [79:0]  feature_duration;

    top_parser_extracao_features #(
        .L3_OFFSET(4),
        .INVALIDATE_AFTER_SEND(1'b1),
        .SCAN_ENTRIES(SCAN_ENTRIES_TB)
    ) dut (
        .clk            (clk),
        .reset          (reset),

        .TDATA          (TDATA),
        .TKEEP          (TKEEP),
        .TVALID         (TVALID),
        .TLAST          (TLAST),
        .TUSER          (TUSER),
        .timestamp_in   (timestamp_in),

        .pcap_done      (pcap_done),

        .feature_vector (feature_vector),
        .fin_done       (fin_done)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    function automatic longint unsigned read_u32_le(input integer f);
        integer b0, b1, b2, b3;
        begin
            b0 = $fgetc(f);
            b1 = $fgetc(f);
            b2 = $fgetc(f);
            b3 = $fgetc(f);

            if ((b0 < 0) || (b1 < 0) || (b2 < 0) || (b3 < 0))
                read_u32_le = 64'hFFFF_FFFF_FFFF_FFFF;
            else
                read_u32_le =
                    (longint'(b0 & 8'hFF)      ) |
                    (longint'(b1 & 8'hFF) <<  8) |
                    (longint'(b2 & 8'hFF) << 16) |
                    (longint'(b3 & 8'hFF) << 24);
        end
    endfunction

    task automatic skip_bytes(input integer f, input integer n);
        integer k;
        integer dummy;
        begin
            for (k = 0; k < n; k = k + 1)
                dummy = $fgetc(f);
        end
    endtask

    task automatic send_frame(
        input integer frame_len,
        input logic [79:0] frame_ts
    );
        integer base_off;
        integer lane;
        integer nbytes;
        begin
            base_off = 0;

            while (base_off < frame_len) begin
                nbytes = frame_len - base_off;
                if (nbytes > 8)
                    nbytes = 8;

                @(negedge clk);

                TDATA        = 64'd0;
                TKEEP        = 8'd0;
                TVALID       = 1'b1;
                TLAST        = ((base_off + nbytes) >= frame_len);
                TUSER        = 1'b1;
                timestamp_in = frame_ts;

                for (lane = 0; lane < nbytes; lane = lane + 1) begin
                    TDATA[lane*8 +: 8] = frame[base_off + lane];
                    TKEEP[lane] = 1'b1;
                end

                base_off = base_off + nbytes;
            end

            @(negedge clk);
            TVALID = 1'b0;
            TLAST  = 1'b0;
            TDATA  = '0;
            TKEEP  = '0;

            repeat (GAP_CLOCKS) @(posedge clk);
        end
    endtask

    // ------------------------------------------------------------------------
    // Contadores de observabilidade
    // ------------------------------------------------------------------------

    // Parser liberou metadados validos.
    always @(posedge clk) begin
        if (!reset && dut.parser_valid)
            parser_valid_count = parser_valid_count + 1;
    end

    // Controller terminou o processamento de um pacote.
    // lookup_result: 01=MISS, 10=HIT, 11=COLLISION.
    always @(posedge clk) begin
        if (!reset && dut.u_features.u_controller.lookup_done) begin
            lookup_count = lookup_count + 1;

            case (dut.u_features.u_controller.lookup_result)
                2'b01: miss_count = miss_count + 1;
                2'b10: hit_count  = hit_count + 1;
                2'b11: collision_count_observed = collision_count_observed + 1;
                default: begin
                    $display("WARN: lookup_done com lookup_result=%b",
                             dut.u_features.u_controller.lookup_result);
                end
            endcase
        end
    end

    // Cada fin_done representa uma feature produzida pelo Finalizer.
    always @(posedge clk) begin
        if (!reset && fin_done) begin
            #1;

            feature_count    = feature_count + 1;
            feature_key      = feature_vector[247:144];
            feature_packets  = feature_vector[143:112];
            feature_bytes    = feature_vector[111:80];
            feature_duration = feature_vector[79:0];

            $fwrite(csv_fd,
                    "%0d,%026h,%0d,%0d,%020h\n",
                    feature_count,
                    feature_key,
                    feature_packets,
                    feature_bytes,
                    feature_duration);

            if ((feature_count % 500) == 0)
                $display("Features coletadas: %0d", feature_count);
        end
    end

    initial begin
        reset        = 1'b1;
        TDATA        = '0;
        TKEEP        = '0;
        TVALID       = 1'b0;
        TLAST        = 1'b0;
        TUSER        = 1'b1;
        timestamp_in = '0;
        pcap_done    = 1'b0;

        records_sent             = 0;
        parser_valid_count       = 0;
        lookup_count             = 0;
        miss_count               = 0;
        hit_count                = 0;
        collision_count_observed = 0;
        feature_count            = 0;
        errors                   = 0;

        repeat (5) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;

        fd = $fopen(PCAP_FILE, "rb");
        if (fd == 0) begin
            $display("ERRO: nao foi possivel abrir %s", PCAP_FILE);
            $finish;
        end

        csv_fd = $fopen(CSV_FILE, "w");
        if (csv_fd == 0) begin
            $display("ERRO: nao foi possivel criar %s", CSV_FILE);
            $finish;
        end

        $fwrite(csv_fd,
                "feature_id,flow_key_hex,packet_count,byte_count,duration_hex\n");

        // Header global PCAP classic = 24 bytes.
        skip_bytes(fd, 24);

        $display("======================================================");
        $display("INICIO: PCAP grande ponta a ponta");
        $display("Arquivo: %s", PCAP_FILE);
        $display("Registros alvo: %0d", MAX_RECORDS);
        $display("L3_OFFSET: 4 (DLT_NULL)");
        $display("Gap entre quadros: %0d clocks", GAP_CLOCKS);
        $display("======================================================");

        pkt_idx = 0;

        while (pkt_idx < MAX_RECORDS) begin
            ts_sec = read_u32_le(fd);

            // EOF.
            if (ts_sec == 64'hFFFF_FFFF_FFFF_FFFF) begin
                $display("EOF apos %0d registros.", pkt_idx);
                pkt_idx = MAX_RECORDS;
            end else begin
                ts_usec  = read_u32_le(fd);
                incl_len = read_u32_le(fd);
                orig_len = read_u32_le(fd);

                if ((incl_len == 64'hFFFF_FFFF_FFFF_FFFF) ||
                    (incl_len > 65536)) begin
                    $display("ERRO: cabecalho PCAP invalido no registro %0d.", pkt_idx + 1);
                    $finish;
                end

                for (i = 0; i < incl_len; i = i + 1) begin
                    c = $fgetc(fd);
                    if (c < 0) begin
                        $display("ERRO: EOF inesperado no registro %0d.", pkt_idx + 1);
                        $finish;
                    end
                    frame[i] = c[7:0];
                end

                ns_part = ts_usec * 1000;
                timestamp_tod = {ts_sec[47:0], ns_part};

                send_frame(incl_len, timestamp_tod);

                pkt_idx = pkt_idx + 1;
                records_sent = records_sent + 1;

                if ((records_sent % 500) == 0) begin
                    $display("Registros enviados: %0d/%0d | Parser valid: %0d | lookups: %0d",
                             records_sent, MAX_RECORDS,
                             parser_valid_count, lookup_count);
                end
            end
        end

        $fclose(fd);

        // Deixa a ultima requisicao terminar.
        repeat (100) @(posedge clk);

        $display("");
        $display("---- FIM DA ENTRADA ----");
        $display("Registros PCAP enviados : %0d", records_sent);
        $display("Parser valid observados  : %0d", parser_valid_count);
        $display("Lookups concluidos       : %0d", lookup_count);
        $display("MISS                     : %0d", miss_count);
        $display("HIT                      : %0d", hit_count);
        $display("COLLISION                : %0d", collision_count_observed);

        // Na campanha anterior do Parser, os primeiros 10.000 registros
        // produziram 7.418 metadados validos. Mantemos como cheque de regressao.
        if ((records_sent == 10000) && (parser_valid_count != 7418)) begin
            $display("WARN: Parser valid difere da campanha anterior (esperado 7418, obtido %0d).",
                     parser_valid_count);
        end

        // Com 80 clocks de intervalo, cada valid do Parser deve chegar ao Controller.
        if (lookup_count != parser_valid_count) begin
            $display("FAIL: lookups (%0d) != Parser valid (%0d).",
                     lookup_count, parser_valid_count);
            errors = errors + 1;
        end

        // Dispara a varredura.
        @(negedge clk);
        pcap_done = 1'b1;
        @(negedge clk);
        pcap_done = 1'b0;

        $display("");
        $display("---- PCAP_DONE: iniciando varredura completa ----");

        wait_cycles = 0;
        while ((dut.u_features.u_controller.scan_done !== 1'b1) &&
               (wait_cycles < MAX_FINAL_WAIT_CYCLES)) begin
            @(posedge clk);
            wait_cycles = wait_cycles + 1;
        end

        if (wait_cycles >= MAX_FINAL_WAIT_CYCLES) begin
            $display("FAIL: timeout aguardando scan_done.");
            errors = errors + 1;
        end else begin
            $display("scan_done observado apos %0d clocks.", wait_cycles);
        end

        repeat (20) @(posedge clk);

        $fclose(csv_fd);

        $display("");
        $display("======================================================");
        $display("RESULTADO FINAL - PCAP GRANDE");
        $display("======================================================");
        $display("Registros enviados : %0d", records_sent);
        $display("Parser valid        : %0d", parser_valid_count);
        $display("Lookups             : %0d", lookup_count);
        $display("MISS                : %0d", miss_count);
        $display("HIT                 : %0d", hit_count);
        $display("COLLISION           : %0d", collision_count_observed);
        $display("Features geradas    : %0d", feature_count);
        $display("CSV                  : %s", CSV_FILE);

        if (errors == 0) begin
            $display("PASS: cadeia ponta a ponta processou a campanha sem perda entre Parser e Controller.");
        end else begin
            $display("FAIL: campanha encerrou com %0d erro(s).", errors);
        end
        $display("======================================================");

        $finish;
    end

endmodule

`default_nettype wire
