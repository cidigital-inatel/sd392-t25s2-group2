`timescale 1ns/1ps

module tb_packet_parser_p01_p14;

    localparam int L3_OFFSET = 14;
    localparam string PCAP_FILE = "trafego_referencia_P01_P14.pcap";

    logic clk;
    logic reset;

    logic [63:0] TDATA;
    logic [7:0]  TKEEP;
    logic        TVALID;
    logic        TLAST;
    logic        TUSER;
    logic [79:0] timestamp_in;

    logic [31:0] src_ip;
    logic [31:0] dst_ip;
    logic [15:0] src_port;
    logic [15:0] dst_port;
    logic [7:0]  protocol;
    logic [15:0] packet_length;
    logic [79:0] timestamp;
    logic        valid;

    integer fd;
    integer i;
    integer j;
    integer pkt_idx;
    integer errors;
    integer valid_count;
    integer c;

    logic [7:0] frame [0:65535];

    longint unsigned ts_sec;
    longint unsigned ts_usec;
    longint unsigned incl_len;
    longint unsigned orig_len;
    logic [79:0] ts_ns;

    // ============================================================
    // DUT
    // ============================================================
    packet_parser #(
        .L3_OFFSET(L3_OFFSET)
    ) dut (
        .clk(clk),
        .reset(reset),
        .TDATA(TDATA),
        .TKEEP(TKEEP),
        .TVALID(TVALID),
        .TLAST(TLAST),
        .TUSER(TUSER),
        .timestamp_in(timestamp_in),

        .src_ip(src_ip),
        .dst_ip(dst_ip),
        .src_port(src_port),
        .dst_port(dst_port),
        .protocol(protocol),
        .packet_length(packet_length),
        .timestamp(timestamp),
        .valid(valid)
    );

    // ============================================================
    // Clock
    // ============================================================
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ============================================================
    // Helpers para PCAP classic little-endian
    // ============================================================
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

    // ============================================================
    // Oracle do Parser
    // ============================================================
    task automatic check_output(input integer p);
        logic exp_valid;
        logic [31:0] exp_src_ip, exp_dst_ip;
        logic [15:0] exp_src_port, exp_dst_port;
        logic [7:0]  exp_proto;
        logic [15:0] exp_len;
        logic [79:0] exp_ts;
        begin
            exp_valid    = 1'b0;
            exp_src_ip   = '0;
            exp_dst_ip   = '0;
            exp_src_port = '0;
            exp_dst_port = '0;
            exp_proto    = '0;
            exp_len      = '0;
            exp_ts       = '0;

            case (p)
                1: begin
                    exp_valid=1; exp_src_ip=32'hC0A8010A; exp_dst_ip=32'h08080808;
                    exp_src_port=16'd52100; exp_dst_port=16'd443; exp_proto=8'd6;
                    exp_len=16'd40; exp_ts=80'd1000000000;
                end
                2: begin
                    exp_valid=1; exp_src_ip=32'hC0A8010A; exp_dst_ip=32'h08080808;
                    exp_src_port=16'd52100; exp_dst_port=16'd443; exp_proto=8'd6;
                    exp_len=16'd60; exp_ts=80'd1000100000;
                end
                3: begin
                    exp_valid=1; exp_src_ip=32'hC0A8010A; exp_dst_ip=32'h08080808;
                    exp_src_port=16'd52100; exp_dst_port=16'd443; exp_proto=8'd6;
                    exp_len=16'd52; exp_ts=80'd1000500000;
                end
                4: begin
                    exp_valid=1; exp_src_ip=32'hC0A80114; exp_dst_ip=32'h08080404;
                    exp_src_port=16'd40000; exp_dst_port=16'd53; exp_proto=8'd17;
                    exp_len=16'd28; exp_ts=80'd2000000000;
                end
                5: begin
                    exp_valid=1; exp_src_ip=32'hC0A80114; exp_dst_ip=32'h08080404;
                    exp_src_port=16'd40000; exp_dst_port=16'd53; exp_proto=8'd17;
                    exp_len=16'd36; exp_ts=80'd2000200000;
                end
                6: begin
                    exp_valid=1; exp_src_ip=32'h0A000001; exp_dst_ip=32'h0A000002;
                    exp_src_port=16'd12345; exp_dst_port=16'd80; exp_proto=8'd6;
                    exp_len=16'd44; exp_ts=80'd3000000000;
                end
                7: begin
                    exp_valid=1; exp_src_ip=32'h0A000001; exp_dst_ip=32'h0A000002;
                    exp_src_port=16'd12345; exp_dst_port=16'd80; exp_proto=8'd6;
                    exp_len=16'd80; exp_ts=80'd3000900000;
                end
                8: begin
                    exp_valid=1; exp_src_ip=32'hAC10000A; exp_dst_ip=32'hAC100014;
                    exp_src_port=16'd5000; exp_dst_port=16'd5001; exp_proto=8'd17;
                    exp_len=16'd28; exp_ts=80'd4000000000;
                end
                default: begin
                    exp_valid = 1'b0; // P09..P14 devem ser descartados
                end
            endcase

            if (p <= 8) begin
                // A chamada é feita quando o pulso valid aparece.
                if ((src_ip        !== exp_src_ip)   ||
                    (dst_ip        !== exp_dst_ip)   ||
                    (src_port      !== exp_src_port) ||
                    (dst_port      !== exp_dst_port) ||
                    (protocol      !== exp_proto)    ||
                    (packet_length !== exp_len)      ||
                    (timestamp     !== exp_ts)) begin

                    $display("FAIL P%02d", p);
                    $display("  obtido  src=%h dst=%h sport=%0d dport=%0d proto=%0d len=%0d ts=%0d",
                             src_ip, dst_ip, src_port, dst_port, protocol, packet_length, timestamp);
                    $display("  esperado src=%h dst=%h sport=%0d dport=%0d proto=%0d len=%0d ts=%0d",
                             exp_src_ip, exp_dst_ip, exp_src_port, exp_dst_port,
                             exp_proto, exp_len, exp_ts);
                    errors = errors + 1;
                end else begin
                    $display("PASS P%02d: src=%h dst=%h sport=%0d dport=%0d proto=%0d len=%0d ts=%0d",
                             p, src_ip, dst_ip, src_port, dst_port,
                             protocol, packet_length, timestamp);
                end
            end
        end
    endtask

    // ============================================================
    // Envia um quadro do PCAP pela interface de 64 bits
    // byte 0 -> TDATA[7:0]
    // ============================================================
    task automatic send_frame(
        input integer p,
        input integer frame_len,
        input logic [79:0] frame_ts
    );
        integer base;
        integer lane;
        integer nbytes;
        logic tuser_final;
        begin
            tuser_final = (p == 12) ? 1'b0 : 1'b1;

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
                TUSER        = TLAST ? tuser_final : 1'b1;
                timestamp_in = frame_ts;

                for (lane = 0; lane < nbytes; lane = lane + 1) begin
                    TDATA[lane*8 +: 8] = frame[base + lane];
                    TKEEP[lane] = 1'b1;
                end

                @(posedge clk);
                #1;

                if (valid) begin
                    valid_count = valid_count + 1;
                    check_output(p);
                end

                base = base + nbytes;
            end

            @(negedge clk);
            TVALID = 1'b0;
            TLAST  = 1'b0;
            TUSER  = 1'b1;
            TDATA  = '0;
            TKEEP  = '0;

            // Pequena janela para detectar valid indevido depois do TLAST.
            @(posedge clk);
            #1;
            if (valid) begin
                valid_count = valid_count + 1;
                check_output(p);
            end

            // P09..P14 não podem produzir valid.
            if ((p >= 9) && valid) begin
                $display("FAIL P%02d: pacote que deveria ser descartado gerou valid.", p);
                errors = errors + 1;
            end
        end
    endtask

    // ============================================================
    // Test
    // ============================================================
    initial begin
        reset        = 1'b1;
        TDATA        = '0;
        TKEEP        = '0;
        TVALID       = 1'b0;
        TLAST        = 1'b0;
        TUSER        = 1'b1;
        timestamp_in = '0;
        errors       = 0;
        valid_count  = 0;
        pkt_idx      = 0;

        repeat (4) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;

        fd = $fopen(PCAP_FILE, "rb");
        if (fd == 0) begin
            $display("ERRO: nao foi possivel abrir %s", PCAP_FILE);
            $finish;
        end

        // PCAP global header = 24 bytes.
        // O arquivo de referência é classic PCAP little-endian / Ethernet II.
        skip_bytes(fd, 24);

        for (pkt_idx = 1; pkt_idx <= 14; pkt_idx = pkt_idx + 1) begin
            ts_sec   = read_u32_le(fd);
            ts_usec  = read_u32_le(fd);
            incl_len = read_u32_le(fd);
            orig_len = read_u32_le(fd);

            if (incl_len > 65536) begin
                $display("ERRO P%02d: incl_len invalido = %0d", pkt_idx, incl_len);
                errors = errors + 1;
                $finish;
            end

            for (i = 0; i < incl_len; i = i + 1) begin
                c = $fgetc(fd);
                if (c < 0) begin
                    $display("ERRO: EOF inesperado em P%02d byte %0d", pkt_idx, i);
                    errors = errors + 1;
                    $finish;
                end
                frame[i] = c[7:0];
            end

            // PCAP usa timestamps em microssegundos.
            // Contrato desta campanha: timestamp de 80 bits como nanosegundos escalares.
            ts_ns = (ts_sec * 80'd1000000000) + (ts_usec * 80'd1000);

            $display("---- P%02d incl_len=%0d orig_len=%0d ts_ns=%0d ----",
                     pkt_idx, incl_len, orig_len, ts_ns);

            send_frame(pkt_idx, incl_len, ts_ns);
        end

        $fclose(fd);

        repeat (3) @(posedge clk);

        if (valid_count != 8) begin
            $display("FAIL: esperados 8 pulsos de valid, obtidos %0d.", valid_count);
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("");
            $display("==============================================");
            $display("PASS: campanha Ethernet II P01-P14 concluida.");
            $display("8 pacotes aceitos e 6 descartados.");
            $display("==============================================");
        end else begin
            $display("");
            $display("==============================================");
            $display("FAIL: campanha concluida com %0d erro(s).", errors);
            $display("==============================================");
        end

        $finish;
    end

endmodule
