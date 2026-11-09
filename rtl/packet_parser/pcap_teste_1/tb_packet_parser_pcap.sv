`timescale 1ns/1ps
`default_nettype none

module tb_packet_parser_direto_pcap;

    localparam string PCAP_FILE = "teste.pcap";

    localparam integer CLOCK_PERIOD_NS = 10;
    localparam integer MAX_FRAME_BYTES = 65536;
    localparam integer MAX_PACKETS = 10000;

    // PCAP DLT_NULL / BSD loopback
    localparam integer DLT_NULL = 0;

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

    integer pcap_fd;
    integer byte_ok;
    integer i;
    integer packet_number;
    integer included_length;
    integer original_length;
    integer pcap_link_type;
    integer valid_count;

    logic pcap_little_endian;
    logic pcap_fraction_is_ns;
    logic global_header_ok;

    logic [31:0] record_timestamp_seconds;
    logic [31:0] record_timestamp_fraction;

    logic [7:0] global_header [0:23];
    logic [7:0] record_header [0:15];
    logic [7:0] frame_bytes [0:MAX_FRAME_BYTES-1];

    packet_parser #(
        .TS_WIDTH (80),
        .L3_OFFSET(4)
    ) dut (
        .clk          (clk),
        .reset        (reset),
        .TDATA        (TDATA),
        .TKEEP        (TKEEP),
        .TVALID       (TVALID),
        .TLAST        (TLAST),
        .TUSER        (TUSER),
        .timestamp_in (timestamp_in),

        .src_ip       (src_ip),
        .dst_ip       (dst_ip),
        .src_port     (src_port),
        .dst_port     (dst_port),
        .protocol     (protocol),
        .packet_length(packet_length),
        .timestamp    (timestamp),
        .valid        (valid)
    );

    initial clk = 1'b0;
    always #(CLOCK_PERIOD_NS/2) clk = ~clk;

    function automatic [31:0] decode_u32(
        input logic [7:0] b0,
        input logic [7:0] b1,
        input logic [7:0] b2,
        input logic [7:0] b3,
        input logic little_endian
    );
        begin
            if (little_endian)
                decode_u32 = {b3,b2,b1,b0};
            else
                decode_u32 = {b0,b1,b2,b3};
        end
    endfunction

    function automatic [7:0] keep_from_bytes(input integer n);
        begin
            case (n)
                1: keep_from_bytes = 8'h01;
                2: keep_from_bytes = 8'h03;
                3: keep_from_bytes = 8'h07;
                4: keep_from_bytes = 8'h0F;
                5: keep_from_bytes = 8'h1F;
                6: keep_from_bytes = 8'h3F;
                7: keep_from_bytes = 8'h7F;
                8: keep_from_bytes = 8'hFF;
                default: keep_from_bytes = 8'h00;
            endcase
        end
    endfunction

    task automatic read_pcap_byte(
        output logic [7:0] value,
        output integer ok
    );
        integer c;
        begin
            c = $fgetc(pcap_fd);
            if (c < 0) begin
                value = 8'd0;
                ok = 0;
            end else begin
                value = c[7:0];
                ok = 1;
            end
        end
    endtask

    task automatic drive_idle;
        begin
            TDATA  = 64'd0;
            TKEEP  = 8'd0;
            TVALID = 1'b0;
            TLAST  = 1'b0;
            TUSER  = 1'b0;
        end
    endtask

    task automatic make_timestamp80(
        input  logic [31:0] seconds_i,
        input  logic [31:0] fraction_i,
        output logic [79:0] timestamp_o
    );
        longint unsigned ns_part;
        begin
            if (pcap_fraction_is_ns)
                ns_part = fraction_i;
            else
                ns_part = longint'(fraction_i) * 64'd1000;

            timestamp_o = {16'd0, seconds_i, ns_part[31:0]};
        end
    endtask

    task automatic read_global_header;
        reg [31:0] magic;
        begin
            global_header_ok = 1'b1;

            for (i = 0; i < 24; i = i + 1) begin
                read_pcap_byte(global_header[i], byte_ok);
                if (!byte_ok)
                    global_header_ok = 1'b0;
            end

            magic = {
                global_header[0],
                global_header[1],
                global_header[2],
                global_header[3]
            };

            case (magic)
                32'hD4C3B2A1: begin
                    pcap_little_endian = 1'b1;
                    pcap_fraction_is_ns = 1'b0;
                end
                32'h4D3CB2A1: begin
                    pcap_little_endian = 1'b1;
                    pcap_fraction_is_ns = 1'b1;
                end
                32'hA1B2C3D4: begin
                    pcap_little_endian = 1'b0;
                    pcap_fraction_is_ns = 1'b0;
                end
                32'hA1B23C4D: begin
                    pcap_little_endian = 1'b0;
                    pcap_fraction_is_ns = 1'b1;
                end
                default: global_header_ok = 1'b0;
            endcase

            pcap_link_type = decode_u32(
                global_header[20], global_header[21],
                global_header[22], global_header[23],
                pcap_little_endian
            );

            if (pcap_link_type != DLT_NULL) begin
                $display("ERRO: link-type=%0d; esperado DLT_NULL=0.", pcap_link_type);
                global_header_ok = 1'b0;
            end
        end
    endtask

    task automatic send_frame(
        input integer frame_length,
        input logic [79:0] packet_ts
    );
        integer word_total;
        integer word_index;
        integer start_index;
        integer valid_bytes;
        integer byte_index;
        logic [63:0] data_word;
        logic [7:0] keep_word;
        begin
            word_total = (frame_length + 7) / 8;

            for (word_index = 0;
                 word_index < word_total;
                 word_index = word_index + 1) begin

                @(negedge clk);

                if (word_index == 0)
                    timestamp_in = packet_ts;

                start_index = word_index * 8;
                valid_bytes = frame_length - start_index;
                if (valid_bytes > 8)
                    valid_bytes = 8;

                data_word = 64'd0;

                // Mesmo lane ordering da frente de verificação:
                // primeiro byte em TDATA[7:0].
                for (byte_index = 0;
                     byte_index < valid_bytes;
                     byte_index = byte_index + 1) begin

                    data_word[(8*byte_index) +: 8] =
                        frame_bytes[start_index + byte_index];
                end

                keep_word = keep_from_bytes(valid_bytes);

                TDATA  = data_word;
                TKEEP  = keep_word;
                TVALID = 1'b1;
                TLAST  = (word_index == word_total-1);
                TUSER  = (word_index == word_total-1);

                @(posedge clk);
                #1ps;
            end

            @(negedge clk);
            drive_idle();
        end
    endtask

    always @(posedge clk) begin
        if (!reset && valid) begin
            valid_count = valid_count + 1;

            $display(
                "PARSER VALID #%0d: src=%08h dst=%08h sport=%0d dport=%0d proto=%0d len=%0d ts=%020h sec=%0d ns=%0d",
                valid_count,
                src_ip,
                dst_ip,
                src_port,
                dst_port,
                protocol,
                packet_length,
                timestamp,
                timestamp[79:32],
                timestamp[31:0]
            );
        end
    end

    initial begin
        logic [79:0] packet_ts;
        integer record_ok;

        reset = 1'b1;
        timestamp_in = '0;
        drive_idle();
        valid_count = 0;
        packet_number = 0;

        repeat (3) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;

        pcap_fd = $fopen(PCAP_FILE, "rb");

        if (pcap_fd == 0)
            $fatal(1, "Nao foi possivel abrir %s", PCAP_FILE);

        read_global_header();

        if (!global_header_ok)
            $fatal(1, "Cabecalho global PCAP invalido.");

        $display("PCAP aberto: DLT_NULL=0.");

        while (!$feof(pcap_fd) && packet_number < MAX_PACKETS) begin

            record_ok = 1;

            for (i = 0; i < 16; i = i + 1) begin
                read_pcap_byte(record_header[i], byte_ok);
                if (!byte_ok)
                    record_ok = 0;
            end

            if (record_ok) begin
                record_timestamp_seconds = decode_u32(
                    record_header[0], record_header[1],
                    record_header[2], record_header[3],
                    pcap_little_endian
                );

                record_timestamp_fraction = decode_u32(
                    record_header[4], record_header[5],
                    record_header[6], record_header[7],
                    pcap_little_endian
                );

                included_length = decode_u32(
                    record_header[8], record_header[9],
                    record_header[10], record_header[11],
                    pcap_little_endian
                );

                original_length = decode_u32(
                    record_header[12], record_header[13],
                    record_header[14], record_header[15],
                    pcap_little_endian
                );

                if ((included_length <= 0) ||
                    (included_length > MAX_FRAME_BYTES)) begin
                    $fatal(1, "Tamanho de quadro invalido: %0d", included_length);
                end

                for (i = 0; i < included_length; i = i + 1) begin
                    read_pcap_byte(frame_bytes[i], byte_ok);
                    if (!byte_ok)
                        $fatal(1, "EOF inesperado dentro de pacote.");
                end

                packet_number = packet_number + 1;

                make_timestamp80(
                    record_timestamp_seconds,
                    record_timestamp_fraction,
                    packet_ts
                );

                send_frame(included_length, packet_ts);
            end
        end

        repeat (10) @(posedge clk);

        $display("PCAP records enviados = %0d", packet_number);
        $display("Metadados validos liberados pelo Parser = %0d", valid_count);
        $display("OBS: IPv4/TCP/UDP suportados geram valid; IPv6/ICMP/outros sao descartados.");

        $fclose(pcap_fd);
        $finish;
    end

endmodule

`default_nettype wire
