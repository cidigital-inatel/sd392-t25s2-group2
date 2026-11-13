`timescale 1ns/1ps
`default_nettype none

// ============================================================================
// Testbench ponta a ponta:
// PCAP -> AXI Stream -> Parser -> FIU -> Hash -> Controller -> Flow Table
//      -> Flow Finalizer -> feature_vector
//
// Primeira campanha funcional:
//   - envia P01-P08
//   - TUSER=1 (quadro valido segundo o Parser validado)
//   - 80 clocks de folga apos cada quadro, preservando o contrato usado
//     na integracao da frente de features
//   - ao final pulsa pcap_done para iniciar a varredura
//   - espera 4 features (F1-F4) e as confere automaticamente
// ============================================================================
module tb_top_parser_extracao_features;

    localparam string PCAP_FILE = "trafego_referencia_P01_P14.pcap";
    localparam int GAP_CLOCKS = 80;

    // O maior hash esperado nesta campanha e 40984.
    // 40985 entradas bastam para a varredura funcional P01-P08.
    localparam int SCAN_ENTRIES_TB = 40985;
    localparam int MAX_WAIT_CYCLES = 300000;

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
    integer c;
    integer i;
    integer pkt_idx;
    integer errors;
    integer feature_count;
    integer wait_cycles;

    longint unsigned ts_sec;
    longint unsigned ts_usec;
    longint unsigned incl_len;
    longint unsigned orig_len;

    logic [31:0] ns_part;
    logic [79:0] timestamp_tod;

    logic seen_f1, seen_f2, seen_f3, seen_f4;

    top_parser_extracao_features #(
        .L3_OFFSET(14),
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
        integer base;
        integer lane;
        integer nbytes;
        begin
            base = 0;

            while (base < frame_len) begin
                nbytes = frame_len - base;
                if (nbytes > 8)
                    nbytes = 8;

                @(negedge clk);

                TDATA        = 64'd0;
                TKEEP        = 8'd0;
                TVALID       = 1'b1;
                TLAST        = ((base + nbytes) >= frame_len);
                TUSER        = 1'b1;
                timestamp_in = frame_ts;

                for (lane = 0; lane < nbytes; lane = lane + 1) begin
                    TDATA[lane*8 +: 8] = frame[base + lane];
                    TKEEP[lane] = 1'b1;
                end

                base = base + nbytes;
            end

            @(negedge clk);
            TVALID = 1'b0;
            TLAST  = 1'b0;
            TDATA  = '0;
            TKEEP  = '0;

            repeat (GAP_CLOCKS) @(posedge clk);
        end
    endtask

    task automatic check_feature;
        logic [103:0] key;
        logic [31:0]  packet_count;
        logic [31:0]  byte_count;
        logic [79:0]  duration;

        logic [31:0] exp_packets;
        logic [31:0] exp_bytes;
        logic [79:0] exp_duration;
        begin
            key          = feature_vector[247:144];
            packet_count = feature_vector[143:112];
            byte_count   = feature_vector[111:80];
            duration     = feature_vector[79:0];

            exp_packets  = '0;
            exp_bytes    = '0;
            exp_duration = '0;

            case (key)
                {32'hC0A8010A,32'h08080808,16'd52100,16'd443,8'd6}: begin
                    exp_packets  = 32'd3;
                    exp_bytes    = 32'd152;
                    exp_duration = {48'd0,32'd500000};
                    if (seen_f1) begin
                        $display("FAIL: F1 duplicado");
                        errors = errors + 1;
                    end
                    seen_f1 = 1'b1;
                end

                {32'hC0A80114,32'h08080404,16'd40000,16'd53,8'd17}: begin
                    exp_packets  = 32'd2;
                    exp_bytes    = 32'd64;
                    exp_duration = {48'd0,32'd200000};
                    if (seen_f2) begin
                        $display("FAIL: F2 duplicado");
                        errors = errors + 1;
                    end
                    seen_f2 = 1'b1;
                end

                {32'h0A000001,32'h0A000002,16'd12345,16'd80,8'd6}: begin
                    exp_packets  = 32'd2;
                    exp_bytes    = 32'd124;
                    exp_duration = {48'd0,32'd900000};
                    if (seen_f3) begin
                        $display("FAIL: F3 duplicado");
                        errors = errors + 1;
                    end
                    seen_f3 = 1'b1;
                end

                {32'hAC10000A,32'hAC100014,16'd5000,16'd5001,8'd17}: begin
                    exp_packets  = 32'd1;
                    exp_bytes    = 32'd28;
                    exp_duration = {48'd0,32'd0};
                    if (seen_f4) begin
                        $display("FAIL: F4 duplicado");
                        errors = errors + 1;
                    end
                    seen_f4 = 1'b1;
                end

                default: begin
                    $display("FAIL: feature com flow_key inesperada: %h", key);
                    errors = errors + 1;
                end
            endcase

            if ((key == {32'hC0A8010A,32'h08080808,16'd52100,16'd443,8'd6}) ||
                (key == {32'hC0A80114,32'h08080404,16'd40000,16'd53,8'd17}) ||
                (key == {32'h0A000001,32'h0A000002,16'd12345,16'd80,8'd6}) ||
                (key == {32'hAC10000A,32'hAC100014,16'd5000,16'd5001,8'd17})) begin

                if ((packet_count !== exp_packets) ||
                    (byte_count   !== exp_bytes) ||
                    (duration     !== exp_duration)) begin

                    $display("FAIL FEATURE #%0d key=%h", feature_count, key);
                    $display(" obtido:   packets=%0d bytes=%0d duration=%h",
                             packet_count, byte_count, duration);
                    $display(" esperado: packets=%0d bytes=%0d duration=%h",
                             exp_packets, exp_bytes, exp_duration);
                    errors = errors + 1;
                end else begin
                    $display("PASS FEATURE #%0d key=%h packets=%0d bytes=%0d duration=%h",
                             feature_count, key, packet_count, byte_count, duration);
                end
            end
        end
    endtask

    always @(posedge clk) begin
        if (!reset && fin_done) begin
            feature_count = feature_count + 1;
            #1;
            check_feature();
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

        errors        = 0;
        feature_count = 0;
        seen_f1       = 1'b0;
        seen_f2       = 1'b0;
        seen_f3       = 1'b0;
        seen_f4       = 1'b0;

        repeat (5) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;

        fd = $fopen(PCAP_FILE, "rb");
        if (fd == 0) begin
            $display("ERRO: nao foi possivel abrir %s", PCAP_FILE);
            $finish;
        end

        // Header global PCAP classic = 24 bytes.
        skip_bytes(fd, 24);

        for (pkt_idx = 1; pkt_idx <= 8; pkt_idx = pkt_idx + 1) begin
            ts_sec   = read_u32_le(fd);
            ts_usec  = read_u32_le(fd);
            incl_len = read_u32_le(fd);
            orig_len = read_u32_le(fd);

            if (incl_len > 65536) begin
                $display("ERRO P%02d: incl_len invalido=%0d", pkt_idx, incl_len);
                $finish;
            end

            for (i = 0; i < incl_len; i = i + 1) begin
                c = $fgetc(fd);
                if (c < 0) begin
                    $display("ERRO: EOF inesperado em P%02d", pkt_idx);
                    $finish;
                end
                frame[i] = c[7:0];
            end

            ns_part = ts_usec * 1000;
            timestamp_tod = {ts_sec[47:0], ns_part};

            $display("---- ENVIA P%02d len=%0d sec=%0d ns=%0d ----",
                     pkt_idx, incl_len, ts_sec, ns_part);

            send_frame(incl_len, timestamp_tod);
        end

        $fclose(fd);

        // Aguarda a ultima transacao terminar e inicia a varredura.
        repeat (20) @(posedge clk);

        @(negedge clk);
        pcap_done = 1'b1;
        @(negedge clk);
        pcap_done = 1'b0;

        $display("---- PCAP_DONE: iniciando varredura ----");

        wait_cycles = 0;
        while ((feature_count < 4) && (wait_cycles < MAX_WAIT_CYCLES)) begin
            @(posedge clk);
            wait_cycles = wait_cycles + 1;
        end

        repeat (20) @(posedge clk);

        if (feature_count != 4) begin
            $display("FAIL: esperadas 4 features, obtidas %0d", feature_count);
            errors = errors + 1;
        end

        if (!(seen_f1 && seen_f2 && seen_f3 && seen_f4)) begin
            $display("FAIL: nem todos os quatro fluxos F1-F4 foram observados.");
            errors = errors + 1;
        end

        $display("");
        $display("======================================================");
        if (errors == 0) begin
            $display("PASS: VALIDACAO PONTA A PONTA.");
            $display("PCAP -> Parser -> FIU -> Hash -> Controller -> Flow Table -> Finalizer");
            $display("8 pacotes de entrada, 4 fluxos e 4 features corretas.");
        end else begin
            $display("FAIL: validacao ponta a ponta com %0d erro(s).", errors);
        end
        $display("======================================================");

        $finish;
    end

endmodule

`default_nettype wire
