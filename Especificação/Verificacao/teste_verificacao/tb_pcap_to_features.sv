`timescale 1ns/1ps
`default_nettype none

// Teste de caminho completo:
// PCAP -> interface AXI-stream RX -> packet_parser -> FIU/Hash -> Controller
// -> Flow Table -> Flow Finalizer -> feature_vector.
// Requer os RTLs de extracao de features descritos no README do pacote.
module tb_pcap_to_features;
    localparam integer MAX_FRAME_BYTES = 2048;
    localparam integer SCAN_TIMEOUT = 300000;

    logic clk;
    logic reset_n;
    logic parser_reset;
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
    logic parser_valid;

    logic [247:0] feature_vector;
    logic fin_done;
    logic pcap_done;

    logic [247:0] expected_features [0:3];
    integer feature_count;
    integer accepted_metadata_count;
    integer scan_done_seen;
    integer pcap_fd;
    integer expected_fd;
    integer read_ok;
    integer packet_count;
    integer frame_len;
    integer original_len;
    integer sec_value;
    integer usec_value;
    integer q;
    integer timeout_count;
    integer error_count;
    logic [7:0] global_header [0:23];
    logic [7:0] frame_bytes [0:MAX_FRAME_BYTES-1];
    logic [79:0] packet_timestamp;

    assign parser_reset = ~reset_n;

    packet_parser #(.TS_WIDTH(80)) u_parser (
        .clk(clk), .reset(parser_reset),
        .TDATA(TDATA), .TKEEP(TKEEP), .TVALID(TVALID),
        .TLAST(TLAST), .TUSER(TUSER), .timestamp_in(timestamp_in),
        .src_ip(src_ip), .dst_ip(dst_ip), .src_port(src_port),
        .dst_port(dst_port), .protocol(protocol),
        .packet_length(packet_length), .timestamp(timestamp), .valid(parser_valid)
    );

    top_extracao_features_com_entrada #(
        .INVALIDATE_AFTER_SEND(1'b1),
        .SCAN_ENTRIES(65536)
    ) u_features (
        .clk(clk), .reset_n(reset_n),
        .src_ip_in(src_ip), .dst_ip_in(dst_ip),
        .src_port_in(src_port), .dst_port_in(dst_port),
        .protocol_in(protocol), .packet_length_in(packet_length),
        .timestamp_in(timestamp), .in_valid(parser_valid),
        .pcap_done(pcap_done),
        .feature_vector(feature_vector), .fin_done(fin_done)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task automatic read_byte(output logic [7:0] value, output integer ok);
        integer c;
        begin
            c=$fgetc(pcap_fd);
            if(c<0) begin value=8'h00; ok=0; end
            else begin value=c[7:0]; ok=1; end
        end
    endtask

    task automatic read_u32_le(output integer value, output integer ok);
        logic [7:0] b0,b1,b2,b3;
        integer a,b,c,d;
        begin
            read_byte(b0,a); read_byte(b1,b); read_byte(b2,c); read_byte(b3,d);
            ok=a&b&c&d;
            value={b3,b2,b1,b0};
        end
    endtask

    task automatic drive_one_frame(input integer bytes, input logic [79:0] ts,
                                   input logic final_user);
        integer base;
        integer n;
        integer lane;
        logic [63:0] data_word;
        logic [7:0] keep_word;
        logic last_word;
        begin
            for(base=0;base<bytes;base=base+8) begin
                data_word=64'd0; keep_word=8'h00;
                n=((bytes-base)>=8)?8:(bytes-base);
                for(lane=0;lane<n;lane=lane+1) begin
                    data_word[63-(8*lane) -: 8]=frame_bytes[base+lane];
                    keep_word[7-lane]=1'b1;
                end
                last_word=((base+n)>=bytes);
                @(negedge clk);
                TDATA=data_word; TKEEP=keep_word; TVALID=1'b1;
                TLAST=last_word; TUSER=last_word?final_user:1'b0;
                timestamp_in=ts;
                @(posedge clk);
            end
            // Libera o barramento apos TLAST. Manter TVALID/TLAST altos
            // durante a pausa faria o Parser interpretar o mesmo beat como
            // varios quadros adicionais.
            @(negedge clk);
            TVALID=1'b0; TLAST=1'b0; TUSER=1'b0; TKEEP=8'h00; TDATA=64'd0;
            // A FIU/Hash/Controller nao possui FIFO nem ready. O intervalo
            // conservador de 80 clocks evita enviar novo pacote durante BUSY.
            repeat(80) @(posedge clk);
        end
    endtask

    // Captura features no clock oposto ao da atualizacao do Finalizer.
    always @(negedge clk) begin
        if (fin_done) begin
            if (feature_count >= 4) begin
                $display("FAIL: feature_vector excedente: %062h",feature_vector);
                error_count=error_count+1;
            end else if (feature_vector !== expected_features[feature_count]) begin
                $display("FAIL feature[%0d]: esperado=%062h recebido=%062h",
                         feature_count,expected_features[feature_count],feature_vector);
                error_count=error_count+1;
            end else begin
                $display("PASS feature[%0d] = %062h",feature_count,feature_vector);
            end
            feature_count=feature_count+1;
        end
    end

    always @(posedge clk) begin
        if (parser_valid) accepted_metadata_count=accepted_metadata_count+1;
        if (u_features.u_controller.scan_done) scan_done_seen=1;
    end

    initial begin
        reset_n=1'b0; TDATA='0; TKEEP='0; TVALID=1'b0;
        TLAST=1'b0; TUSER=1'b0; timestamp_in='0; pcap_done=1'b0;
        feature_count=0; accepted_metadata_count=0; scan_done_seen=0;
        packet_count=0; timeout_count=0; error_count=0;

        // Vetores calculados pelo modelo de referência Python (248 bits por linha).
        expected_fd=$fopen("feature_vectors_esperados.mem","r");
        if(expected_fd==0) $fatal(1,"Nao foi possivel abrir feature_vectors_esperados.mem");
        $fclose(expected_fd);
        $readmemh("feature_vectors_esperados.mem",expected_features);

        repeat(4) @(posedge clk);
        @(negedge clk); reset_n=1'b1;

        pcap_fd=$fopen("trafego_referencia_P01_P14.pcap","rb");
        if(pcap_fd==0) $fatal(1,"Nao foi possivel abrir trafego_referencia_P01_P14.pcap");
        for(q=0;q<24;q=q+1) begin
            read_byte(global_header[q],read_ok);
            if(!read_ok) $fatal(1,"Cabecalho global PCAP truncado");
        end
        if(global_header[0]!=8'hD4 || global_header[1]!=8'hC3 ||
           global_header[2]!=8'hB2 || global_header[3]!=8'hA1)
            $fatal(1,"PCAP deve ser classic little-endian usec");
        if(global_header[20]!=8'h01 || global_header[21]!=8'h00 ||
           global_header[22]!=8'h00 || global_header[23]!=8'h00)
            $fatal(1,"PCAP deve usar DLT_EN10MB");

        while(1) begin
            read_u32_le(sec_value,read_ok);
            if(!read_ok) break;
            read_u32_le(usec_value,read_ok);
            if(!read_ok) $fatal(1,"registro PCAP truncado em usec");
            read_u32_le(frame_len,read_ok);
            if(!read_ok) $fatal(1,"registro PCAP truncado em incl_len");
            read_u32_le(original_len,read_ok);
            if(!read_ok) $fatal(1,"registro PCAP truncado em orig_len");
            if(frame_len<1 || frame_len>MAX_FRAME_BYTES || frame_len>original_len)
                $fatal(1,"comprimento de quadro invalido: %0d",frame_len);
            for(q=0;q<frame_len;q=q+1) begin
                read_byte(frame_bytes[q],read_ok);
                if(!read_ok) $fatal(1,"payload PCAP truncado");
            end
            packet_count=packet_count+1;
            packet_timestamp=({48'd0,sec_value[31:0]}*80'd1000000000)+
                             ({48'd0,usec_value[31:0]}*80'd1000);
            // O PCAP nao registra TUSER. P12 e marcado como quadro invalido,
            // conforme a matriz P01-P14; os demais recebem TUSER=1.
            drive_one_frame(frame_len,packet_timestamp,(packet_count==12)?1'b0:1'b1);
        end
        $fclose(pcap_fd);

        if(packet_count!=14) $fatal(1,"Esperados 14 quadros; recebidos %0d",packet_count);
        if(accepted_metadata_count!=8)
            $fatal(1,"Esperados 8 metadados validos; recebidos %0d",accepted_metadata_count);

        @(negedge clk); pcap_done=1'b1;
        @(negedge clk); pcap_done=1'b0;

        while((scan_done_seen==0) && (timeout_count<SCAN_TIMEOUT)) begin
            @(posedge clk); timeout_count=timeout_count+1;
        end
        repeat(2) @(posedge clk);

        $display("\n===== RESUMO PCAP -> PACKET PARSER -> FEATURES =====");
        $display("Quadros PCAP lidos:       %0d",packet_count);
        $display("Metadados aceitos:        %0d",accepted_metadata_count);
        $display("Feature vectors esperados:%0d",4);
        $display("Feature vectors recebidos:%0d",feature_count);
        $display("Ciclos de varredura:      %0d",timeout_count);
        $display("Erros:                    %0d",error_count);

        if(scan_done_seen && feature_count==4 && error_count==0) begin
            $display("PASS: integracao PCAP -> Parser -> FIU/Hash -> Controller/Flow Table -> Finalizer.");
            $finish;
        end else begin
            $fatal(1,"FAIL: integracao incompleta ou divergente");
        end
    end
endmodule

`default_nettype wire
