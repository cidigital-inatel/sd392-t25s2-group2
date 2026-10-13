
`timescale 1ns/1ps

module tb_controller;

    logic clk;
    logic reset;

    logic [15:0]  hash_index;
    logic [103:0] flow_key;
    logic [15:0]  packet_length;
    logic [79:0]  timestamp;
    logic         hash_valid;

    logic         rd_en;
    logic [20:0]  rd_addr;
    logic [31:0]  rd_data;
    logic         rd_valid;
    logic [383:0] flow_entry;

    logic [31:0] memory [0:4095];

    logic pending_read;
    logic [20:0] pending_addr;

    logic [20:0] expected_base;

    integer errors;
    integer reads_seen;
    integer i;

    controller dut (
        .clk           (clk),
        .reset         (reset),
        .hash_index    (hash_index),
        .flow_key      (flow_key),
        .packet_length (packet_length),
        .timestamp     (timestamp),
        .hash_valid    (hash_valid),
        .rd_en         (rd_en),
        .rd_addr       (rd_addr),
        .rd_data       (rd_data),
        .rd_valid      (rd_valid),
        .flow_entry    (flow_entry)
    );

    // Clock de 100 MHz: periodo de 10 ns
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Modelo comportamental da Flow Table
    always_ff @(posedge clk) begin
        if (reset) begin
            rd_data      <= '0;
            rd_valid     <= 1'b0;
            pending_read <= 1'b0;
            pending_addr <= '0;
        end else begin
            rd_valid <= pending_read;

            if (pending_read)
                rd_data <= memory[pending_addr];

            pending_read <= rd_en;

            if (rd_en)
                pending_addr <= rd_addr;
        end
    end

    // Monitor de enderecos de leitura
    always @(posedge clk) begin
        if (reset) begin
            reads_seen <= 0;
        end else if (rd_en) begin
            if (rd_addr !== expected_base + reads_seen) begin
                $error(
                    "Endereco incorreto: esperado=%0d, recebido=%0d",
                    expected_base + reads_seen,
                    rd_addr
                );
                errors = errors + 1;
            end

            reads_seen <= reads_seen + 1;
        end
    end

    // Executa um cenario de LOOKUP
    task automatic run_lookup(input logic [15:0] test_hash);
        logic [20:0] test_base;
        integer j;

        begin
            test_base = {1'b0, test_hash, 4'b0000};

            // Aguarda o Controller estar em IDLE
            @(negedge clk);
            while (dut.state != dut.IDLE)
                @(negedge clk);

            // Prepara a memoria e os contadores
            expected_base = test_base;
            reads_seen = 0;

            for (j = 0; j < 5; j = j + 1)
                memory[test_base + j] = 32'hA0000000 + j;

            // Aplica os metadados
            hash_index    = test_hash;
            flow_key      = 104'h123456789ABCDEF123456789AB;
            packet_length = 16'd128;
            timestamp     = 80'd1234;
            hash_valid    = 1'b1;

            // O Controller captura os metadados nesta borda
            @(negedge clk);
            hash_valid = 1'b0;

            // Confirma a captura e o pulso interno de start
            wait (dut.start == 1'b1);

            // Aguarda a conclusao das cinco leituras
            wait (dut.state == dut.LOOKUP_DONE);
            @(negedge clk);

            // Verifica as palavras recebidas
            for (j = 0; j < 5; j = j + 1) begin
                if (flow_entry[j*32 +: 32] !==
                    (32'hA0000000 + j)) begin
                    $error(
                        "W%0d incorreta: esperado=%h, recebido=%h",
                        j,
                        32'hA0000000 + j,
                        flow_entry[j*32 +: 32]
                    );
                    errors = errors + 1;
                end
            end

            // Verifica os bits nao utilizados
            if (flow_entry[383:160] !== 224'b0) begin
                $error("flow_entry[383:160] deveria permanecer zerado.");
                errors = errors + 1;
            end

            // Verifica a quantidade de leituras
            if (reads_seen != 5) begin
                $error(
                    "Quantidade incorreta de leituras: %0d",
                    reads_seen
                );
                errors = errors + 1;
            end

            if (errors == 0) begin
                $display(
                    "PASSOU: hash_index=%0d, base=%0d, leituras=%0d",
                    test_hash,
                    test_base,
                    reads_seen
                );
            end

            // Aguarda o retorno a IDLE antes do proximo teste
            wait (dut.state == dut.IDLE);
            @(negedge clk);
        end
    endtask

    // Inicializacao e execucao dos testes
    initial begin
        reset         = 1'b1;
        hash_index    = '0;
        flow_key      = '0;
        packet_length = '0;
        timestamp     = '0;
        hash_valid    = 1'b0;

        rd_data       = '0;
        rd_valid      = 1'b0;
        pending_read  = 1'b0;
        pending_addr  = '0;

        expected_base = '0;
        errors        = 0;
        reads_seen    = 0;

        for (i = 0; i < 4096; i = i + 1)
            memory[i] = '0;

        repeat (3) @(negedge clk);
        reset = 1'b0;

        run_lookup(16'd0);
        run_lookup(16'd5);
        run_lookup(16'd100);

        if (errors == 0)
            $display("TODOS OS TESTES PASSARAM!");
        else
            $display("TESTES FINALIZADOS COM %0d ERRO(S).", errors);

        #20;
        $finish;
    end

    // Timeout de seguranca
    initial begin
        #100000;
        $fatal(1, "TIMEOUT: o LOOKUP nao terminou.");
    end

endmodule
