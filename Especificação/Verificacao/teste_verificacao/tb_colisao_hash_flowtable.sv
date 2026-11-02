`timescale 1ns/1ps
`default_nettype none

// Teste dirigido da politica de colisao:
// duas chaves distintas produzem o mesmo CRC16 (0x58BC).
// A primeira deve ser armazenada (MISS); a segunda deve ser descartada
// sem sobrescrever a entrada (COLLISION).
// A entrada deste teste equivale aos metadados ja produzidos pelo Parser.
module tb_colisao_hash_flowtable;
    localparam integer HASH_INDEX = 16'h58BC;
    localparam integer SCAN_ENTRIES = HASH_INDEX + 1;
    localparam integer MEM_BASE = HASH_INDEX * 16;
    localparam integer LOOKUP_TIMEOUT = 300;
    localparam integer SCAN_TIMEOUT = 100000;

    localparam logic [103:0] KEY_A = 104'h0A011A89C000020108C801BB06;
    localparam logic [103:0] KEY_B = 104'h0A013BB4C000020155F401BB06;

    logic clk;
    logic reset_n;
    logic [31:0] src_ip_in;
    logic [31:0] dst_ip_in;
    logic [15:0] src_port_in;
    logic [15:0] dst_port_in;
    logic [7:0] protocol_in;
    logic [15:0] packet_length_in;
    logic [79:0] timestamp_in;
    logic in_valid;
    logic pcap_done;
    logic [247:0] feature_vector;
    logic fin_done;

    logic [247:0] expected_feature;
    logic [103:0] stored_key;
    integer timeout_count;
    integer feature_count;
    integer scan_done_seen;
    integer error_count;

    top_extracao_features_com_entrada #(
        .INVALIDATE_AFTER_SEND(1'b1),
        .SCAN_ENTRIES(SCAN_ENTRIES)
    ) dut (
        .clk(clk),
        .reset_n(reset_n),
        .src_ip_in(src_ip_in),
        .dst_ip_in(dst_ip_in),
        .src_port_in(src_port_in),
        .dst_port_in(dst_port_in),
        .protocol_in(protocol_in),
        .packet_length_in(packet_length_in),
        .timestamp_in(timestamp_in),
        .in_valid(in_valid),
        .pcap_done(pcap_done),
        .feature_vector(feature_vector),
        .fin_done(fin_done)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Conta e compara a unica feature que deve sobreviver a colisao.
    always @(negedge clk) begin
        if (fin_done) begin
            feature_count = feature_count + 1;
            if (feature_vector !== expected_feature) begin
                $display("FAIL: feature recebida=%062h esperada=%062h",
                         feature_vector, expected_feature);
                error_count = error_count + 1;
            end else begin
                $display("PASS: feature preservou somente a chave original apos colisao: %062h",
                         feature_vector);
            end
        end
    end

    always @(posedge clk) begin
        if (dut.u_controller.scan_done)
            scan_done_seen = 1;
    end

    task automatic send_and_check(
        input logic [31:0] src_ip,
        input logic [31:0] dst_ip,
        input logic [15:0] src_port,
        input logic [15:0] dst_port,
        input logic [7:0] proto,
        input logic [15:0] length_bytes,
        input logic [79:0] timestamp_ns,
        input logic [1:0] expected_result,
        input integer packet_number
    );
        integer local_timeout;
        begin
            @(negedge clk);
            src_ip_in = src_ip;
            dst_ip_in = dst_ip;
            src_port_in = src_port;
            dst_port_in = dst_port;
            protocol_in = proto;
            packet_length_in = length_bytes;
            timestamp_in = timestamp_ns;
            in_valid = 1'b1;

            @(negedge clk);
            in_valid = 1'b0;

            local_timeout = 0;
            while ((dut.u_controller.lookup_done !== 1'b1) &&
                   (local_timeout < LOOKUP_TIMEOUT)) begin
                @(negedge clk);
                local_timeout = local_timeout + 1;
            end

            if (dut.u_controller.lookup_done !== 1'b1)
                $fatal(1, "Timeout esperando lookup_done no pacote %0d", packet_number);

            if (dut.hash_index !== HASH_INDEX)
                $fatal(1, "Hash incorreto no pacote %0d: esperado=%04h recebido=%04h",
                       packet_number, HASH_INDEX, dut.hash_index);

            if (dut.u_controller.lookup_result !== expected_result)
                $fatal(1, "Classificacao incorreta no pacote %0d: esperada=%b recebida=%b",
                       packet_number, expected_result, dut.u_controller.lookup_result);

            if (packet_number == 1)
                $display("PASS pacote 1: MISS no indice %04h", dut.hash_index);
            else
                $display("PASS pacote 2: COLLISION no indice %04h", dut.hash_index);

            // Deixa hash_valid retornar a zero e o Controller voltar a IDLE.
            repeat (5) @(posedge clk);
        end
    endtask

    initial begin
        reset_n = 1'b0;
        src_ip_in = '0;
        dst_ip_in = '0;
        src_port_in = '0;
        dst_port_in = '0;
        protocol_in = '0;
        packet_length_in = '0;
        timestamp_in = '0;
        in_valid = 1'b0;
        pcap_done = 1'b0;
        expected_feature = {KEY_A, 32'd1, 32'd40, 80'd0};
        stored_key = '0;
        timeout_count = 0;
        feature_count = 0;
        scan_done_seen = 0;
        error_count = 0;

        if (KEY_A == KEY_B)
            $fatal(1, "Erro no vetor dirigido: as chaves deveriam ser diferentes");

        repeat (4) @(posedge clk);
        @(negedge clk);
        reset_n = 1'b1;

        $display("\n===== TESTE DIRIGIDO DE COLISAO CRC16 =====");
        $display("Chave A: %026h", KEY_A);
        $display("Chave B: %026h", KEY_B);
        $display("Hash esperado para ambas: %04h", HASH_INDEX);

        // Chave A: 10.1.26.137:2248 -> 192.0.2.1:443 / TCP.
        // Deve ocupar o slot 0x58BC.
        send_and_check(
            32'h0A011A89, 32'hC0000201, 16'd2248, 16'd443, 8'd6,
            16'd40, 80'd1000000000, 2'b01, 1
        );

        // Confere o registro criado pelo primeiro pacote.
        stored_key = {
            dut.u_flow_table.mem[MEM_BASE+4][7:0],
            dut.u_flow_table.mem[MEM_BASE+3],
            dut.u_flow_table.mem[MEM_BASE+2],
            dut.u_flow_table.mem[MEM_BASE+1]
        };
        if (dut.u_flow_table.mem[MEM_BASE] !== 32'd1 ||
            stored_key !== KEY_A ||
            dut.u_flow_table.mem[MEM_BASE+5] !== 32'd1 ||
            dut.u_flow_table.mem[MEM_BASE+6] !== 32'd40)
            $fatal(1, "Flow Table nao armazenou corretamente a chave A no MISS");

        // Chave B: 10.1.59.180:22004 -> 192.0.2.1:443 / TCP.
        // CRC e igual, mas a chave e diferente: deve ocorrer COLLISION.
        send_and_check(
            32'h0A013BB4, 32'hC0000201, 16'd22004, 16'd443, 8'd6,
            16'd60, 80'd1000100000, 2'b11, 2
        );

        if (dut.u_controller.collision_count !== 32'd1)
            $fatal(1, "collision_count esperado=1; recebido=%0d",
                   dut.u_controller.collision_count);

        // A colisao nao pode sobrescrever a entrada existente nem somar bytes.
        stored_key = {
            dut.u_flow_table.mem[MEM_BASE+4][7:0],
            dut.u_flow_table.mem[MEM_BASE+3],
            dut.u_flow_table.mem[MEM_BASE+2],
            dut.u_flow_table.mem[MEM_BASE+1]
        };
        if (dut.u_flow_table.mem[MEM_BASE] !== 32'd1 ||
            stored_key !== KEY_A ||
            dut.u_flow_table.mem[MEM_BASE+5] !== 32'd1 ||
            dut.u_flow_table.mem[MEM_BASE+6] !== 32'd40)
            $fatal(1, "COLLISION alterou a entrada original da Flow Table");

        $display("PASS: collision_count=1; entrada original preservada; pacote B descartado");

        // Exporta apenas o fluxo A. A varredura termina no indice 0x58BC.
        @(negedge clk);
        pcap_done = 1'b1;
        @(negedge clk);
        pcap_done = 1'b0;

        while ((scan_done_seen == 0) && (timeout_count < SCAN_TIMEOUT)) begin
            @(negedge clk);
            timeout_count = timeout_count + 1;
        end

        if (scan_done_seen == 0)
            $fatal(1, "Timeout esperando scan_done no teste de colisao");

        repeat (2) @(negedge clk);

        if (feature_count != 1)
            $fatal(1, "Esperada 1 feature apos colisao; recebidas %0d", feature_count);
        if (error_count != 0)
            $fatal(1, "Erros na comparacao de feature: %0d", error_count);
        if (dut.u_flow_table.mem[MEM_BASE] !== 32'd0)
            $fatal(1, "Entrada deveria ser invalidada apos exportacao");

        $display("\n===== RESUMO TESTE DE COLISAO =====");
        $display("Hash A/B:                 %04h / %04h", HASH_INDEX, HASH_INDEX);
        $display("Classificacao pacote A:   MISS");
        $display("Classificacao pacote B:   COLLISION");
        $display("collision_count:          %0d", dut.u_controller.collision_count);
        $display("Features exportadas:      %0d", feature_count);
        $display("Ciclos ate scan_done:     %0d", timeout_count);
        $display("Erros:                    %0d", error_count);
        $display("PASS: politica de colisao preserva a entrada ocupada e descarta a nova chave.");
        $finish;
    end
endmodule

`default_nettype wire
