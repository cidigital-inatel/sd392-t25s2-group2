`timescale 1ns / 1ps

// =====================================================================
// TESTE DE INTEGRACAO DO TOPO: Controller + Flow Table + Flow Finalizer
//
// Fluxos (indice da Flow Table):
//   A (3)  : 2 pacotes
//   B (7)  : 1 pacote
//   C (11) : 3 pacotes
//   D (5)  : 2 pacotes, timestamps maiores
//   E (9)  : 5 pacotes
//   F (ultimo indice): 2 pacotes enviados com hash_valid de 1 ciclo,
//                      chave com o byte alto diferente de zero e
//                      timestamps de 80 bits que atravessam W7-W9 / W10-W12
//   + 1 pacote COLLISION no indice do fluxo A (deve ser descartado)
//
// Depois: varredura (pcap_done), conferencia dos vetores, ordem de chegada,
// duplicidade, invalidacao das entradas e uma segunda varredura sem reenvio.
//
// Para varrer a tabela inteira, troque SCAN_ENTRIES para 65536.
// =====================================================================
module tb_top_extracao_features;

    localparam int SCAN_ENTRIES = 16;          // 65536 = tabela completa
    localparam int MAX_VECTORS  = 16;
    localparam int NUM_FLOWS    = 6;

    // Ciclos de relogio que uma varredura pode levar (com folga)
    localparam int SCAN_CYCLES  = SCAN_ENTRIES * 8 + 5000;

    // Ultimo indice varrido
    localparam logic [15:0] LAST_IDX = SCAN_ENTRIES - 1;

    logic clk;
    logic rst;

    logic [15:0]  hash_index;
    logic [103:0] flow_key;
    logic [15:0]  packet_length;
    logic [79:0]  timestamp;
    logic         hash_valid;
    logic         pcap_done;

    logic [247:0] feature_vector;
    logic         fin_done;

    integer received_count;
    integer scan_done_count = 0;
    logic [247:0] received_vectors [0:MAX_VECTORS-1];

    localparam logic [103:0] KEY_A = 104'h123456789ABCDEF;
    localparam logic [103:0] KEY_B = 104'hFEDCBA987654321;
    localparam logic [103:0] KEY_C = 104'h112233445566778;
    localparam logic [103:0] KEY_D = 104'hABCDEF123456789;
    localparam logic [103:0] KEY_E = 104'h987654321ABCDEF;
    // Chave de 104 bits completos (byte alto diferente de zero)
    localparam logic [103:0] KEY_F = 104'hA5123456789ABCDEF012345678;

    // Timestamps de 80 bits que atravessam as tres palavras (W7-W9 e W10-W12)
    localparam logic [79:0] TS_F1 = 80'h0001_FFFF_FFFF_FFFF_FFF0;
    localparam logic [79:0] TS_F2 = 80'h0002_0000_0000_0000_0010;   // TS_F2 - TS_F1 = 32

    // Indice e chave de cada fluxo, na ordem em que a varredura os entrega
    logic [15:0]  scan_idx_order [0:NUM_FLOWS-1];
    logic [103:0] scan_key_order [0:NUM_FLOWS-1];

    // =================================================
    // DUT
    // =================================================

    top_extracao_features #(
        .INVALIDATE_AFTER_SEND(1'b1),
        .SCAN_ENTRIES(SCAN_ENTRIES)
    ) dut (
        .clk(clk),
        .rst(rst),
        .hash_index(hash_index),
        .flow_key(flow_key),
        .packet_length(packet_length),
        .timestamp(timestamp),
        .hash_valid(hash_valid),
        .pcap_done(pcap_done),
        .feature_vector(feature_vector),
        .fin_done(fin_done)
    );

    // =================================================
    // CLOCK
    // =================================================

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // =================================================
    // WATCHDOG GLOBAL
    // =================================================

    initial begin
        #(10 * (3 * SCAN_CYCLES + 50000));
        $fatal(1, "TIMEOUT global da testbench");
    end

    // =================================================
    // CAPTURA DOS VETORES (um por ciclo com fin_done = 1)
    // =================================================

    always @(posedge clk) begin
        if (rst) begin
            received_count <= 0;
        end
        else if (fin_done) begin
            if (received_count < MAX_VECTORS) begin
                received_vectors[received_count] <= feature_vector;
                received_count <= received_count + 1;

                $display("[%0d ns] Feature %0d recebida: %h",
                         $time, received_count + 1, feature_vector);
            end
            else begin
                $fatal(1, "ERRO: limite de vetores excedido");
            end
        end
    end

    // Conta os pulsos de fim de varredura (sinal interno do Controller)
    always @(posedge clk) begin
        if (!rst && dut.u_controller.scan_done === 1'b1)
            scan_done_count <= scan_done_count + 1;
    end

    // =================================================
    // ENVIO DE PACOTE: hash_valid mantido ate o fim da operacao
    // =================================================

    task automatic send_packet(
        input logic [15:0]  idx,
        input logic [103:0] key,
        input logic [15:0]  length_bytes,
        input logic [79:0]  packet_timestamp
    );
        begin
            @(negedge clk);

            hash_index    = idx;
            flow_key      = key;
            packet_length = length_bytes;
            timestamp     = packet_timestamp;
            hash_valid    = 1'b1;

            wait (dut.u_controller.lookup_done === 1'b1);

            @(negedge clk);
            hash_valid = 1'b0;

            wait (dut.u_controller.lookup_done === 1'b0);

            repeat (2) @(negedge clk);
        end
    endtask

    // =================================================
    // ENVIO DE PACOTE: hash_valid de 1 ciclo (uso mais provavel no sistema)
    // =================================================

    task automatic send_packet_pulse(
        input logic [15:0]  idx,
        input logic [103:0] key,
        input logic [15:0]  length_bytes,
        input logic [79:0]  packet_timestamp
    );
        begin
            @(negedge clk);

            hash_index    = idx;
            flow_key      = key;
            packet_length = length_bytes;
            timestamp     = packet_timestamp;
            hash_valid    = 1'b1;

            @(negedge clk);
            hash_valid = 1'b0;

            // Entradas embaralhadas: o Controller ja deve ter capturado tudo
            hash_index    = 16'hFFFF;
            flow_key      = '1;
            packet_length = 16'hFFFF;
            timestamp     = '1;

            wait (dut.u_controller.lookup_done === 1'b1);
            wait (dut.u_controller.lookup_done === 1'b0);

            repeat (3) @(negedge clk);
        end
    endtask

    // =================================================
    // CONFERENCIA DE UM FLUXO
    // =================================================

    task automatic check_flow(
        input logic [103:0] expected_key,
        input logic [31:0]  expected_packets,
        input logic [31:0]  expected_bytes,
        input logic [79:0]  expected_duration
    );

        integer k;
        integer match_count;

        begin
            match_count = 0;

            for (k = 0; k < received_count; k = k + 1) begin

                if (received_vectors[k][247:144] === expected_key) begin
                    match_count = match_count + 1;

                    if (received_vectors[k][143:112] !== expected_packets)
                        $fatal(1, "ERRO: packet_count incorreto para %h (obtido %0d, esperado %0d)",
                               expected_key, received_vectors[k][143:112], expected_packets);

                    if (received_vectors[k][111:80] !== expected_bytes)
                        $fatal(1, "ERRO: byte_count incorreto para %h (obtido %0d, esperado %0d)",
                               expected_key, received_vectors[k][111:80], expected_bytes);

                    if (received_vectors[k][79:0] !== expected_duration)
                        $fatal(1, "ERRO: duration incorreta para %h (obtida %0d, esperada %0d)",
                               expected_key, received_vectors[k][79:0], expected_duration);
                end
            end

            if (match_count != 1)
                $fatal(1,
                    "ERRO: esperado 1 vetor para %h, encontrados %0d",
                    expected_key, match_count);

            $display("PASSOU: chave=%h | pacotes=%0d | bytes=%0d | duracao=%0d",
                     expected_key,
                     expected_packets,
                     expected_bytes,
                     expected_duration);
        end
    endtask

    // =================================================
    // INICIA VARREDURA (pcap_done em pulso)
    // =================================================

    task automatic start_scan;
        begin
            @(negedge clk);
            pcap_done = 1'b1;

            @(negedge clk);
            pcap_done = 1'b0;
        end
    endtask

    // =================================================
    // AGUARDA O FIM DA N-ESIMA VARREDURA
    // =================================================

    task automatic wait_for_scan(input integer expected_scans);

        integer timeout;

        begin
            timeout = 0;

            while (scan_done_count < expected_scans) begin
                @(posedge clk);
                timeout = timeout + 1;

                if (timeout > SCAN_CYCLES)
                    $fatal(1,
                        "TIMEOUT: a varredura %0d nao terminou (vetores recebidos: %0d)",
                        expected_scans, received_count);
            end

            repeat (5) @(negedge clk);
        end
    endtask

    // =================================================
    // TESTES
    // =================================================

    integer k;

    initial begin

        // Inicializacao
        rst = 1'b1;
        hash_index = '0;
        flow_key = '0;
        packet_length = '0;
        timestamp = '0;
        hash_valid = 1'b0;
        pcap_done = 1'b0;
        received_count = 0;

        // Ordem em que a varredura entrega os fluxos (por indice crescente)
        scan_idx_order[0] = 16'd3;     scan_key_order[0] = KEY_A;
        scan_idx_order[1] = 16'd5;     scan_key_order[1] = KEY_D;
        scan_idx_order[2] = 16'd7;     scan_key_order[2] = KEY_B;
        scan_idx_order[3] = 16'd9;     scan_key_order[3] = KEY_E;
        scan_idx_order[4] = 16'd11;    scan_key_order[4] = KEY_C;
        scan_idx_order[5] = LAST_IDX;  scan_key_order[5] = KEY_F;

        repeat (5) @(negedge clk);
        rst = 1'b0;

        // -------------------------------------------------
        // TESTE 1: fluxo A - dois pacotes
        // -------------------------------------------------

        $display("\nTESTE 1: Fluxo A - dois pacotes");

        send_packet(16'd3, KEY_A, 16'd100, 80'd1000);
        send_packet(16'd3, KEY_A, 16'd200, 80'd1050);

        // -------------------------------------------------
        // TESTE 2: fluxo B - um pacote
        // -------------------------------------------------

        $display("\nTESTE 2: Fluxo B - um pacote");

        send_packet(16'd7, KEY_B, 16'd300, 80'd2000);

        // -------------------------------------------------
        // TESTE 3: fluxo C - tres pacotes
        // -------------------------------------------------

        $display("\nTESTE 3: Fluxo C - tres pacotes");

        send_packet(16'd11, KEY_C, 16'd64,  80'd5000);
        send_packet(16'd11, KEY_C, 16'd128, 80'd5100);
        send_packet(16'd11, KEY_C, 16'd256, 80'd5200);

        // -------------------------------------------------
        // TESTE 4: fluxo D - timestamps maiores
        // -------------------------------------------------

        $display("\nTESTE 4: Fluxo D - timestamps maiores");

        send_packet(16'd5, KEY_D, 16'd512, 80'd1000000);
        send_packet(16'd5, KEY_D, 16'd512, 80'd1500000);

        // -------------------------------------------------
        // TESTE 5: fluxo E - varios pacotes
        // -------------------------------------------------

        $display("\nTESTE 5: Fluxo E - varios pacotes");

        send_packet(16'd9, KEY_E, 16'd100, 80'd10000);
        send_packet(16'd9, KEY_E, 16'd200, 80'd10100);
        send_packet(16'd9, KEY_E, 16'd300, 80'd10200);
        send_packet(16'd9, KEY_E, 16'd400, 80'd10300);
        send_packet(16'd9, KEY_E, 16'd500, 80'd10400);

        // -------------------------------------------------
        // TESTE 6: fluxo F - chave de 104 bits, timestamps de 80 bits
        //          e hash_valid de 1 ciclo, no ultimo indice
        // -------------------------------------------------

        $display("\nTESTE 6: Fluxo F - chave completa, timestamps de 80 bits, valid de 1 ciclo");

        send_packet_pulse(LAST_IDX, KEY_F, 16'd100, TS_F1);
        send_packet_pulse(LAST_IDX, KEY_F, 16'd100, TS_F2);

        // -------------------------------------------------
        // TESTE 7: COLLISION pelo topo
        // -------------------------------------------------

        $display("\nTESTE 7: COLLISION no indice do fluxo A");

        // Chave diferente no indice 3: deve ser descartada
        send_packet(16'd3, KEY_B, 16'd999, 80'd3000);

        if (dut.u_controller.collision_count !== 32'd1)
            $fatal(1, "ERRO: collision_count=%0d esperado=1",
                   dut.u_controller.collision_count);

        $display("PASSOU: collision_count = 1 (o fluxo A sera conferido na varredura).");

        // -------------------------------------------------
        // TESTE 8: varredura da Flow Table
        // -------------------------------------------------

        $display("\nTESTE 8: Varredura da Flow Table");

        start_scan();
        wait_for_scan(1);

        // -------------------------------------------------
        // TESTE 9: quantidade de features
        // -------------------------------------------------

        $display("\nTESTE 9: Quantidade de features");

        if (received_count != NUM_FLOWS)
            $fatal(1,
                "ERRO: esperados %0d vetores; recebidos %0d",
                NUM_FLOWS, received_count);

        $display("PASSOU: %0d fluxos encontrados.", NUM_FLOWS);

        // -------------------------------------------------
        // TESTE 10: conferencia individual
        // -------------------------------------------------

        $display("\nTESTE 10: Conferencia das features");

        check_flow(KEY_A, 32'd2, 32'd300,  80'd50);       // COLLISION nao altera o fluxo A
        check_flow(KEY_B, 32'd1, 32'd300,  80'd0);
        check_flow(KEY_C, 32'd3, 32'd448,  80'd200);
        check_flow(KEY_D, 32'd2, 32'd1024, 80'd500000);
        check_flow(KEY_E, 32'd5, 32'd1500, 80'd400);
        check_flow(KEY_F, 32'd2, 32'd200,  80'd32);       // 80 bits atravessando W7-W9 / W10-W12

        // -------------------------------------------------
        // TESTE 11: ordem de chegada (indice crescente)
        // -------------------------------------------------

        $display("\nTESTE 11: Ordem dos vetores (indice crescente)");

        for (k = 0; k < NUM_FLOWS; k = k + 1) begin
            if (received_vectors[k][247:144] !== scan_key_order[k])
                $fatal(1, "ERRO: vetor %0d fora de ordem (chave %h, esperada %h)",
                       k, received_vectors[k][247:144], scan_key_order[k]);
        end

        $display("PASSOU: a varredura entregou os fluxos na ordem dos indices.");

        // -------------------------------------------------
        // TESTE 12: duplicidade
        // -------------------------------------------------

        $display("\nTESTE 12: Verificacao de duplicidade");

        repeat (20) @(negedge clk);

        if (received_count != NUM_FLOWS)
            $fatal(1, "ERRO: foram recebidos vetores adicionais (%0d)",
                   received_count);

        $display("PASSOU: nenhum vetor duplicado.");

        // -------------------------------------------------
        // TESTE 13: invalidacao das entradas e segunda varredura
        // -------------------------------------------------

        $display("\nTESTE 13: Verificacao de invalidacao");

        // As entradas enviadas ao Finalizer devem estar com valid = 0
        for (k = 0; k < NUM_FLOWS; k = k + 1) begin
            if (dut.u_flow_table.mem[scan_idx_order[k] * 16][0] !== 1'b0)
                $fatal(1, "ERRO: a entrada %0d nao foi invalidada",
                       scan_idx_order[k]);
        end

        // Uma nova varredura nao pode reenviar nenhum fluxo
        start_scan();
        wait_for_scan(2);

        if (received_count != NUM_FLOWS)
            $fatal(1,
                "ERRO: entradas invalidadas foram enviadas novamente (%0d vetores)",
                received_count);

        $display("PASSOU: entradas invalidadas e nenhuma reenviada.");

        // -------------------------------------------------
        // RESULTADO FINAL
        // -------------------------------------------------

        $display("\n======================================");
        $display("TODOS OS TESTES PASSARAM!");
        $display("Total de fluxos testados: %0d", received_count);
        $display("======================================");

        $finish;

    end

endmodule