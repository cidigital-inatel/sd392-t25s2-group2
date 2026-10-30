
`timescale 1ns / 1ps

module tb_top_extracao_features;

    localparam int SCAN_ENTRIES = 16;
    localparam int MAX_VECTORS = 16;

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
    logic [247:0] received_vectors [0:MAX_VECTORS-1];

    localparam logic [103:0] KEY_A = 104'h123456789ABCDEF;
    localparam logic [103:0] KEY_B = 104'hFEDCBA987654321;
    localparam logic [103:0] KEY_C = 104'h112233445566778;
    localparam logic [103:0] KEY_D = 104'hABCDEF123456789;
    localparam logic [103:0] KEY_E = 104'h987654321ABCDEF;

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
    // CAPTURA DOS VETORES
    // =================================================

    always @(posedge clk) begin
        if (rst) begin
            received_count <= 0;
        end
        else if (fin_done) begin
            if (received_count < MAX_VECTORS) begin
                received_vectors[received_count] <= feature_vector;
                received_count <= received_count + 1;

                $display("[%0t ns] Feature %0d recebida: %h",
                         $time, received_count + 1, feature_vector);
            end
            else begin
                $fatal(1, "ERRO: limite de vetores excedido");
            end
        end
    end

    // =================================================
    // ENVIO DE PACOTE
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
    // CONFERÊNCIA DE UM FLUXO
    // =================================================

    task automatic check_flow(
        input logic [103:0] expected_key,
        input logic [31:0] expected_packets,
        input logic [31:0] expected_bytes,
        input logic [79:0] expected_duration
    );

        integer k;
        integer match_count;

        begin
            match_count = 0;

            for (k = 0; k < received_count; k = k + 1) begin

                if (received_vectors[k][247:144] === expected_key) begin
                    match_count = match_count + 1;

                    if (received_vectors[k][143:112] !== expected_packets)
                        $fatal(1, "ERRO: packet_count incorreto para %h",
                               expected_key);

                    if (received_vectors[k][111:80] !== expected_bytes)
                        $fatal(1, "ERRO: byte_count incorreto para %h",
                               expected_key);

                    if (received_vectors[k][79:0] !== expected_duration)
                        $fatal(1, "ERRO: duration incorreta para %h",
                               expected_key);
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
    // INICIA VARREDURA
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
    // AGUARDA QUANTIDADE DE FEATURES
    // =================================================

    task automatic wait_for_vectors(input integer expected);

        integer timeout;

        begin
            timeout = 0;

            while (received_count < expected) begin
                @(posedge clk);
                timeout = timeout + 1;

                if (timeout > 10000)
                    $fatal(1,
                        "TIMEOUT: esperados %0d vetores; recebidos %0d",
                        expected, received_count);
            end

            repeat (3) @(negedge clk);
        end
    endtask

    // =================================================
    // TESTES
    // =================================================

    initial begin

        // Inicialização
        rst = 1'b1;
        hash_index = '0;
        flow_key = '0;
        packet_length = '0;
        timestamp = '0;
        hash_valid = 1'b0;
        pcap_done = 1'b0;
        received_count = 0;

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
        // TESTE 3: fluxo C - três pacotes
        // -------------------------------------------------

        $display("\nTESTE 3: Fluxo C - três pacotes");

        send_packet(16'd11, KEY_C, 16'd64, 80'd5000);
        send_packet(16'd11, KEY_C, 16'd128, 80'd5100);
        send_packet(16'd11, KEY_C, 16'd256, 80'd5200);

        // -------------------------------------------------
        // TESTE 4: fluxo D - timestamps maiores
        // -------------------------------------------------

        $display("\nTESTE 4: Fluxo D - timestamps maiores");

        send_packet(16'd5, KEY_D, 16'd512, 80'd1000000);
        send_packet(16'd5, KEY_D, 16'd512, 80'd1500000);

        // Resultado esperado:
        // packet_count = 2
        // byte_count   = 1024
        // duration     = 500000

        // -------------------------------------------------
        // TESTE 5: fluxo E - vários pacotes
        // -------------------------------------------------

        $display("\nTESTE 5: Fluxo E - varios pacotes");

        send_packet(16'd9, KEY_E, 16'd100, 80'd10000);
        send_packet(16'd9, KEY_E, 16'd200, 80'd10100);
        send_packet(16'd9, KEY_E, 16'd300, 80'd10200);
        send_packet(16'd9, KEY_E, 16'd400, 80'd10300);
        send_packet(16'd9, KEY_E, 16'd500, 80'd10400);

        // Resultado esperado:
        // packet_count = 5
        // byte_count   = 1500
        // duration     = 400

        // -------------------------------------------------
        // TESTE 6: varredura da Flow Table
        // -------------------------------------------------

        $display("\nTESTE 6: Varredura da Flow Table");

        start_scan();

        fork
            begin
                wait (received_count >= 5);
            end

            begin
                repeat (10000) @(posedge clk);
                $fatal(1, "TIMEOUT: features nao recebidas");
            end
        join_any

        disable fork;

        repeat (3) @(negedge clk);

        // -------------------------------------------------
        // TESTE 7: quantidade de features
        // -------------------------------------------------

        $display("\nTESTE 7: Quantidade de features");

        if (received_count != 5)
            $fatal(1,
                "ERRO: esperados 5 vetores; recebidos %0d",
                received_count);

        $display("PASSOU: cinco fluxos encontrados.");

        // -------------------------------------------------
        // TESTE 8: conferência individual
        // -------------------------------------------------

        $display("\nTESTE 8: Conferencia das features");

        check_flow(KEY_A, 32'd2, 32'd300, 80'd50);
        check_flow(KEY_B, 32'd1, 32'd300, 80'd0);
        check_flow(KEY_C, 32'd3, 32'd448, 80'd200);
        check_flow(KEY_D, 32'd2, 32'd1024, 80'd500000);
        check_flow(KEY_E, 32'd5, 32'd1500, 80'd400);

        // -------------------------------------------------
        // TESTE 9: duplicidade
        // -------------------------------------------------

        $display("\nTESTE 9: Verificacao de duplicidade");

        repeat (20) @(negedge clk);

        if (received_count != 5)
            $fatal(1,
                "ERRO: foram recebidos vetores adicionais");

        $display("PASSOU: nenhum vetor duplicado.");

        // -------------------------------------------------
        // TESTE 10: invalidação da entrada
        // -------------------------------------------------

        $display("\nTESTE 10: Verificacao de invalidacao");

        // Verifica se uma nova varredura não reenvia
        // as entradas que já foram finalizadas.
        start_scan();

        repeat (10000) @(posedge clk);

        if (received_count != 5)
            $fatal(1,
                "ERRO: entradas invalidadas foram enviadas novamente");

        $display("PASSOU: nenhuma entrada foi reenviada.");

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
