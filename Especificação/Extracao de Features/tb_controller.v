
`timescale 1ns/1ps

module tb_controller;

    reg clk = 1'b0;
    reg reset;

    reg [15:0]  hash_index;
    reg [103:0] flow_key;
    reg [15:0]  packet_length;
    reg [79:0]  timestamp;
    reg         hash_valid;

    reg [15:0]  rd_data;
    reg         rd_valid;
    reg         wr_done;
    reg         fin_done;

    wire        rd_en;
    wire [20:0] rd_addr;

    wire        wr_en;
    wire [20:0] wr_addr;
    wire [15:0] wr_data;

    wire [383:0] flow_entry;
    wire         fin_valid;

    reg [15:0] memory [0:4095];

    reg [20:0] pending_addr;
    reg        pending_read;

    reg [20:0] expected_base;

    integer i;
    integer reads_seen;
    integer errors;
    integer test_number;

    always #5 clk = ~clk;

    controller dut (
        .clk(clk),
        .reset(reset),

        .hash_index(hash_index),
        .flow_key(flow_key),
        .packet_length(packet_length),
        .timestamp(timestamp),
        .hash_valid(hash_valid),

        .rd_data(rd_data),
        .rd_valid(rd_valid),
        .wr_done(wr_done),
        .fin_done(fin_done),

        .rd_en(rd_en),
        .rd_addr(rd_addr),

        .wr_en(wr_en),
        .wr_addr(wr_addr),
        .wr_data(wr_data),

        .flow_entry(flow_entry),
        .fin_valid(fin_valid)
    );

    // --------------------------------------------------
    // Modelo de memória síncrona com latência de leitura.
    // --------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            rd_data      <= 16'd0;
            rd_valid     <= 1'b0;
            pending_addr <= 21'd0;
            pending_read <= 1'b0;
        end else begin
            rd_valid <= pending_read;

            if (pending_read)
                rd_data <= memory[pending_addr];

            pending_read <= rd_en;

            if (rd_en)
                pending_addr <= rd_addr;
        end
    end

    // --------------------------------------------------
    // Monitor de endereços.
    // --------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            reads_seen = 0;
        end else if (rd_en) begin
            if (rd_addr !== (expected_base + reads_seen)) begin
                $display(
                    "ERRO: teste %0d, endereco obtido=%0d, esperado=%0d",
                    test_number,
                    rd_addr,
                    expected_base + reads_seen
                );
                errors = errors + 1;
            end

            reads_seen = reads_seen + 1;
        end
    end

    // --------------------------------------------------
    // Tarefa para testar uma consulta.
    // --------------------------------------------------
    task run_lookup;
        input [15:0]  test_hash;
        input [103:0] test_key;
        input [15:0]  test_length;
        input [79:0]  test_timestamp;

        integer k;
        reg [20:0] calculated_base;

        begin
            test_number = test_number + 1;
            calculated_base = test_hash * 21'd24;

            // Aguarda o Controller ficar livre.
            wait (dut.state == 3'd0);
            wait (dut.start == 1'b0);
            @(negedge clk);

            hash_index    = test_hash;
            flow_key      = test_key;
            packet_length = test_length;
            timestamp     = test_timestamp;

            expected_base = calculated_base;
            reads_seen    = 0;

            // Inicializa as 24 palavras da entrada.
            for (k = 0; k < 24; k = k + 1)
                memory[calculated_base + k] = 16'hA000 + k;

            // Inicia a consulta.
            hash_valid = 1'b1;

            @(negedge clk);
            hash_valid = 1'b0;

            // Verifica os metadados capturados.
            if (dut.hash_index_reg !== test_hash) begin
                $display("ERRO: hash_index_reg incorreto.");
                errors = errors + 1;
            end

            if (dut.flow_key_reg !== test_key) begin
                $display("ERRO: flow_key_reg incorreto.");
                errors = errors + 1;
            end

            if (dut.packet_length_reg !== test_length) begin
                $display("ERRO: packet_length_reg incorreto.");
                errors = errors + 1;
            end

            if (dut.timestamp_reg !== test_timestamp) begin
                $display("ERRO: timestamp_reg incorreto.");
                errors = errors + 1;
            end

            // Aguarda as 24 solicitações de leitura.
            wait (reads_seen == 24);

            // Aguarda a conclusão da consulta.
            wait (dut.state == 3'd3);
            @(negedge clk);
            @(negedge clk);

            // Confere todas as palavras do registro.
            for (k = 0; k < 24; k = k + 1) begin
                if (flow_entry[k*16 +: 16] !== (16'hA000 + k)) begin
                    $display(
                        "ERRO: palavra %0d incorreta: obtida=%h, esperada=%h",
                        k,
                        flow_entry[k*16 +: 16],
                        16'hA000 + k
                    );
                    errors = errors + 1;
                end
            end

            if (reads_seen != 24) begin
                $display("ERRO: total de leituras diferente de 24.");
                errors = errors + 1;
            end

            if (wr_en !== 1'b0 || fin_valid !== 1'b0) begin
                $display("ERRO: saida nao utilizada ficou ativa.");
                errors = errors + 1;
            end

            if (errors == 0)
                $display(
                    "Teste %0d passou: hash=%0d, base=%0d",
                    test_number, test_hash, calculated_base
                );
            else
                $display(
                    "Teste %0d terminou com erros acumulados: %0d",
                    test_number, errors
                );
        end
    endtask

    // --------------------------------------------------
    // Estímulos principais.
    // --------------------------------------------------
    initial begin
        reset         = 1'b1;
        hash_index    = 16'd0;
        flow_key      = 104'd0;
        packet_length = 16'd0;
        timestamp     = 80'd0;
        hash_valid    = 1'b0;

        rd_data       = 16'd0;
        rd_valid      = 1'b0;
        wr_done       = 1'b0;
        fin_done      = 1'b0;

        pending_addr  = 21'd0;
        pending_read  = 1'b0;
        expected_base = 21'd0;

        reads_seen    = 0;
        errors        = 0;
        test_number   = 0;

        for (i = 0; i < 4096; i = i + 1)
            memory[i] = 16'd0;

        // Mantém o reset por três bordas de descida.
        repeat (3) @(negedge clk);
        reset = 1'b0;

        // Teste 1: hash_index = 0, base = 0.
        run_lookup(
            16'd0,
            104'h00000000000000000000000001,
            16'd64,
            80'h1001
        );

        // Teste 2: hash_index = 5, base = 120.
        run_lookup(
            16'd5,
            104'h123456789ABCDEF123456789AB,
            16'd128,
            80'h1234
        );

        // Teste 3: hash_index = 100, base = 2400.
        run_lookup(
            16'd100,
            104'h00000000000000000000000064,
            16'd256,
            80'h5678
        );

        if (errors == 0)
            $display(
                "PASSOU: todos os testes foram concluidos sem erros."
            );
        else
            $display("FALHOU: total de erros = %0d", errors);

        $finish;
    end

    // --------------------------------------------------
    // Timeout de segurança.
    // --------------------------------------------------
    initial begin
    #300000;
    $display("TIMEOUT: a simulacao nao terminou.");
    $finish;
end

endmodule
