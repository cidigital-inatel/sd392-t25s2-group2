`timescale 1ns/1ps
`default_nettype none

module tb_packet_parser_pcap;
    localparam integer MAX_FRAME_BYTES = 2048;
    localparam [79:0] TS_P01 = 80'd1000000000;

    logic clk;
    logic reset;
    logic [63:0] TDATA;
    logic [7:0] TKEEP;
    logic TVALID;
    logic TLAST;
    logic TUSER;
    logic [79:0] timestamp_in;

    logic [31:0] src_ip;
    logic [31:0] dst_ip;
    logic [15:0] src_port;
    logic [15:0] dst_port;
    logic [7:0] protocol;
    logic [15:0] packet_length;
    logic [79:0] timestamp;
    logic valid;

    integer pcap_fd;
    integer byte_rc;
    integer header_ok;
    integer packet_number;
    integer packet_total;
    integer observed_valid;
    integer expected_valid;
    integer error_count;
    integer included_length;
    integer original_length;
    integer record_sec;
    integer record_usec;
    integer index;
    integer first_frame_len;
    integer reset_recovery_count;
    integer bad_keep_checked;

    logic [7:0] global_header [0:23];
    logic [7:0] frame_bytes [0:MAX_FRAME_BYTES-1];
    logic [7:0] first_frame_bytes [0:MAX_FRAME_BYTES-1];
    logic [79:0] packet_ts;
    logic [63:0] beat_data;
    logic [7:0] beat_keep;
    integer base;
    integer valid_in_beat;
    integer lane;
    integer last_beat;

    packet_parser #(.TS_WIDTH(80)) dut (
        .clk(clk), .reset(reset),
        .TDATA(TDATA), .TKEEP(TKEEP), .TVALID(TVALID),
        .TLAST(TLAST), .TUSER(TUSER), .timestamp_in(timestamp_in),
        .src_ip(src_ip), .dst_ip(dst_ip), .src_port(src_port),
        .dst_port(dst_port), .protocol(protocol),
        .packet_length(packet_length), .timestamp(timestamp), .valid(valid)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task automatic read_file_byte(output logic [7:0] value, output integer ok);
        integer c;
        begin
            c = $fgetc(pcap_fd);
            if (c < 0) begin value = 8'h00; ok = 0; end
            else begin value = c[7:0]; ok = 1; end
        end
    endtask

    task automatic read_u32_le(output integer value, output integer ok);
        logic [7:0] b0, b1, b2, b3;
        integer o0, o1, o2, o3;
        begin
            read_file_byte(b0, o0);
            read_file_byte(b1, o1);
            read_file_byte(b2, o2);
            read_file_byte(b3, o3);
            ok = o0 & o1 & o2 & o3;
            value = {b3, b2, b1, b0};
        end
    endtask

    task automatic check_expected(input integer p, input logic [79:0] expected_ts);
        logic [31:0] exp_src;
        logic [31:0] exp_dst;
        logic [15:0] exp_sport;
        logic [15:0] exp_dport;
        logic [7:0] exp_proto;
        logic [15:0] exp_len;
        begin
            exp_src = 32'd0; exp_dst = 32'd0;
            exp_sport = 16'd0; exp_dport = 16'd0;
            exp_proto = 8'd0; exp_len = 16'd0;
            case (p)
                1, 2, 3: begin
                    exp_src=32'hC0A8010A; exp_dst=32'h08080808;
                    exp_sport=16'd52100; exp_dport=16'd443; exp_proto=8'd6;
                    if (p==1) exp_len=16'd40;
                    if (p==2) exp_len=16'd60;
                    if (p==3) exp_len=16'd52;
                end
                4, 5: begin
                    exp_src=32'hC0A80114; exp_dst=32'h08080404;
                    exp_sport=16'd40000; exp_dport=16'd53; exp_proto=8'd17;
                    if (p==4) exp_len=16'd28;
                    if (p==5) exp_len=16'd36;
                end
                6, 7: begin
                    exp_src=32'h0A000001; exp_dst=32'h0A000002;
                    exp_sport=16'd12345; exp_dport=16'd80; exp_proto=8'd6;
                    if (p==6) exp_len=16'd44;
                    if (p==7) exp_len=16'd80;
                end
                8: begin
                    exp_src=32'hAC10000A; exp_dst=32'hAC100014;
                    exp_sport=16'd5000; exp_dport=16'd5001;
                    exp_proto=8'd17; exp_len=16'd28;
                end
                default: $fatal(1, "Packet ID invalido para check_expected: %0d", p);
            endcase

            if (valid !== 1'b1) begin
                $display("FAIL %0d: valid=0, esperado 1", p);
                error_count = error_count + 1;
            end
            if (src_ip !== exp_src) begin $display("FAIL %0d src_ip: %08h != %08h",p,src_ip,exp_src); error_count=error_count+1; end
            if (dst_ip !== exp_dst) begin $display("FAIL %0d dst_ip: %08h != %08h",p,dst_ip,exp_dst); error_count=error_count+1; end
            if (src_port !== exp_sport) begin $display("FAIL %0d src_port: %0d != %0d",p,src_port,exp_sport); error_count=error_count+1; end
            if (dst_port !== exp_dport) begin $display("FAIL %0d dst_port: %0d != %0d",p,dst_port,exp_dport); error_count=error_count+1; end
            if (protocol !== exp_proto) begin $display("FAIL %0d protocol: %0d != %0d",p,protocol,exp_proto); error_count=error_count+1; end
            if (packet_length !== exp_len) begin $display("FAIL %0d packet_length: %0d != %0d",p,packet_length,exp_len); error_count=error_count+1; end
            if (timestamp !== expected_ts) begin $display("FAIL %0d timestamp: %0d != %0d",p,timestamp,expected_ts); error_count=error_count+1; end

            if ((src_ip===exp_src) && (dst_ip===exp_dst) &&
                (src_port===exp_sport) && (dst_port===exp_dport) &&
                (protocol===exp_proto) && (packet_length===exp_len) &&
                (timestamp===expected_ts) && (valid===1'b1)) begin
                $display("PASS P%02d: src=%08h dst=%08h sport=%0d dport=%0d proto=%0d len=%0d ts=%0d",
                         p,src_ip,dst_ip,src_port,dst_port,protocol,packet_length,timestamp);
            end
        end
    endtask

    task automatic drive_frame(
        input integer frame_len,
        input logic [79:0] ts,
        input logic final_user,
        input integer packet_id,
        input logic corrupt_keep
    );
        integer b;
        integer n;
        integer j;
        logic [63:0] d;
        logic [7:0] k;
        logic is_last;
        begin
            for (b = 0; b < frame_len; b = b + 8) begin
                d = 64'd0; k = 8'h00;
                n = ((frame_len - b) >= 8) ? 8 : (frame_len - b);
                for (j = 0; j < n; j = j + 1) begin
                    d[63-(8*j) -: 8] = frame_bytes[b+j];
                    k[7-j] = 1'b1;
                end
                is_last = ((b + n) >= frame_len);
                if (corrupt_keep && (b == 8)) k = 8'hA0;

                @(negedge clk);
                TDATA = d;
                TKEEP = k;
                TVALID = 1'b1;
                TLAST = is_last;
                TUSER = is_last ? final_user : 1'b0;
                timestamp_in = ts;
                @(posedge clk); #1;

                if (is_last) begin
                    if ((packet_id >= 1) && (packet_id <= 8)) begin
                        check_expected(packet_id, ts);
                        if (valid === 1'b1) observed_valid = observed_valid + 1;
                    end else begin
                        if (valid !== 1'b0) begin
                            $display("FAIL P%02d: pacote deveria ser descartado, valid=%b", packet_id, valid);
                            error_count = error_count + 1;
                        end else begin
                            $display("PASS P%02d: descartado como esperado", packet_id);
                        end
                    end
                end else if (valid !== 1'b0) begin
                    $display("FAIL P%02d: valid antecipado antes de TLAST",packet_id);
                    error_count = error_count + 1;
                end
            end
        end
    endtask

    task automatic drive_reset_during_frame;
        integer b;
        integer j;
        logic [63:0] d;
        begin
            // Envia os dois primeiros beats de P01 sem TLAST.
            for (b=0; b<16; b=b+8) begin
                d=64'd0;
                for (j=0; j<8; j=j+1)
                    d[63-(8*j) -: 8] = first_frame_bytes[b+j];
                @(negedge clk);
                TDATA=d; TKEEP=8'hFF; TVALID=1'b1; TLAST=1'b0;
                TUSER=1'b0; timestamp_in=TS_P01;
                @(posedge clk); #1;
                if (valid !== 1'b0) $fatal(1,"UT11: valid indevido antes do reset");
            end
            @(negedge clk);
            TVALID=1'b0; TLAST=1'b0; TKEEP=8'h00; TDATA=64'd0; reset=1'b1;
            repeat (3) @(posedge clk);
            @(negedge clk); reset=1'b0;
            repeat (1) @(posedge clk); #1;
            if (valid !== 1'b0) $fatal(1,"UT11: valid permaneceu ativo apos reset");

            // Confirma que o Parser recupera e volta a aceitar um quadro completo.
            for (b=0; b<first_frame_len; b=b+8) begin
                d=64'd0;
                for (j=0; j<8 && (b+j)<first_frame_len; j=j+1)
                    d[63-(8*j) -: 8] = first_frame_bytes[b+j];
                @(negedge clk);
                TDATA=d;
                TKEEP=(first_frame_len-b >= 8) ? 8'hFF :
                    ((first_frame_len-b == 7) ? 8'hFE :
                     (first_frame_len-b == 6) ? 8'hFC :
                     (first_frame_len-b == 5) ? 8'hF8 :
                     (first_frame_len-b == 4) ? 8'hF0 :
                     (first_frame_len-b == 3) ? 8'hE0 :
                     (first_frame_len-b == 2) ? 8'hC0 : 8'h80);
                TVALID=1'b1; TLAST=((b+8)>=first_frame_len);
                TUSER=TLAST ? 1'b1 : 1'b0; timestamp_in=TS_P01;
                @(posedge clk); #1;
                if (TLAST) begin
                    check_expected(1,TS_P01);
                    if (valid===1'b1) reset_recovery_count=reset_recovery_count+1;
                end
            end
            $display("PASS UT11: reset no meio do quadro e recuperacao confirmada");
        end
    endtask

    task automatic drive_bad_tkeep;
        integer q;
        begin
            for (q=0; q<first_frame_len; q=q+1) frame_bytes[q]=first_frame_bytes[q];
            drive_frame(first_frame_len, TS_P01, 1'b1, 15, 1'b1);
            if (valid !== 1'b0) begin
                $display("FAIL UT16: TKEEP nao contiguo foi aceito");
                error_count=error_count+1;
            end else begin
                bad_keep_checked=1;
                $display("PASS UT16: TKEEP nao contiguo descartado");
            end
        end
    endtask

    initial begin
        reset=1'b1; TDATA='0; TKEEP='0; TVALID=1'b0; TLAST=1'b0;
        TUSER=1'b0; timestamp_in='0;
        error_count=0; observed_valid=0; expected_valid=8;
        packet_number=0; packet_total=0; first_frame_len=0;
        reset_recovery_count=0; bad_keep_checked=0;

        repeat (3) @(posedge clk);
        @(negedge clk); reset=1'b0;

        pcap_fd=$fopen("trafego_referencia_P01_P14.pcap","rb");
        if (pcap_fd==0)
            $fatal(1,"Nao foi possivel abrir trafego_referencia_P01_P14.pcap no diretorio de simulacao");

        for (index=0; index<24; index=index+1) begin
            read_file_byte(global_header[index],byte_rc);
            if (!byte_rc) $fatal(1,"PCAP truncado no cabecalho global");
        end
        if ((global_header[0]!==8'hD4) || (global_header[1]!==8'hC3) ||
            (global_header[2]!==8'hB2) || (global_header[3]!==8'hA1))
            $fatal(1,"Magic PCAP inesperado; esperado little-endian usec D4 C3 B2 A1");
        if ((global_header[20]!==8'h01) || (global_header[21]!==8'h00) ||
            (global_header[22]!==8'h00) || (global_header[23]!==8'h00))
            $fatal(1,"PCAP nao usa DLT_EN10MB (Ethernet)");

        // Le registros e conduz cada quadro diretamente para o Packet Parser.
        // Nao existe arquivo TXT intermediario.
        while (1) begin
            read_u32_le(record_sec,header_ok);
            if (!header_ok) break;
            read_u32_le(record_usec,header_ok);
            if (!header_ok) $fatal(1,"PCAP truncado em ts_usec");
            read_u32_le(included_length,header_ok);
            if (!header_ok) $fatal(1,"PCAP truncado em incl_len");
            read_u32_le(original_length,header_ok);
            if (!header_ok) $fatal(1,"PCAP truncado em orig_len");
            if ((included_length<1) || (included_length>MAX_FRAME_BYTES))
                $fatal(1,"incl_len invalido: %0d",included_length);
            if (included_length>original_length)
                $fatal(1,"incl_len maior que orig_len");

            for (index=0; index<included_length; index=index+1) begin
                read_file_byte(frame_bytes[index],byte_rc);
                if (!byte_rc) $fatal(1,"PCAP truncado no payload do registro %0d",packet_total+1);
            end

            packet_number=packet_total+1;
            packet_total=packet_number;
            packet_ts = ({48'd0,record_sec[31:0]} * 80'd1000000000) +
                        ({48'd0,record_usec[31:0]} * 80'd1000);

            if (packet_number==1) begin
                first_frame_len=included_length;
                for (index=0; index<included_length; index=index+1)
                    first_frame_bytes[index]=frame_bytes[index];
            end

            // O PCAP nao carrega TUSER. Conforme a especificacao, somente P12
            // recebe TUSER=0 no ultimo beat; os demais recebem TUSER=1.
            drive_frame(included_length,packet_ts,(packet_number==12)?1'b0:1'b1,
                        packet_number,1'b0);
        end
        $fclose(pcap_fd);

        if (packet_total!=14) begin
            $display("FAIL: esperados 14 registros, lidos %0d",packet_total);
            error_count=error_count+1;
        end
        if (observed_valid!=expected_valid) begin
            $display("FAIL: esperados %0d pulsos valid, observados %0d",expected_valid,observed_valid);
            error_count=error_count+1;
        end

        // UT11: interrupcao por reset no meio de P01, seguida de recuperacao.
        drive_reset_during_frame();
        // UT16: mascara TKEEP com lacuna, que deve provocar descarte.
        drive_bad_tkeep();

        @(negedge clk); TVALID=1'b0; TLAST=1'b0; TUSER=1'b0; TKEEP=8'h00; TDATA='0;
        repeat (2) @(posedge clk); #1;
        if (valid!==1'b0) begin
            $display("FAIL: valid nao voltou a zero apos a campanha");
            error_count=error_count+1;
        end

        $display("\n===== RESUMO PACKET PARSER / PCAP =====");
        $display("Registros PCAP:              %0d",packet_total);
        $display("Metadados validos esperados: %0d",expected_valid);
        $display("Metadados validos observados:%0d",observed_valid);
        $display("UT11 recuperacao por reset:  %0d",reset_recovery_count);
        $display("UT16 TKEEP nao contiguo:     %0d",bad_keep_checked);
        $display("Erros:                       %0d",error_count);
        if (error_count==0 && packet_total==14 && observed_valid==8 &&
            reset_recovery_count==1 && bad_keep_checked==1) begin
            $display("PASS: PCAP DIRETO -> PACKET PARSER; cenarios P01-P14, reset e TKEEP aprovados.");
            $finish;
        end else begin
            $fatal(1,"FAIL: campanha PCAP/Packet Parser encontrou inconsistencias");
        end
    end
endmodule

`default_nettype wire
