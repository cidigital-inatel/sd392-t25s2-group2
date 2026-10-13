
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

    integer errors;
    integer reads_seen;
    integer i;

    logic [20:0] expected_base;

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

    // Clock: periodo de 10 ns
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Modelo simplificado da Flow Table
    // Cada leitura solicitada retorna rd_valid no ciclo seguinte.
    always_ff @(posedge clk) begin
        if (reset) begin
            rd_data     <= 32'b0;
            rd_valid    <= 1'b0;
            pending_read <= 1'b0;
            pending_addr <= 21'b0;
        end else begin
            rd_valid <= pending_read;

            if (pending_read)
                rd_data <= memory[pending_addr];

            pending_read <= rd_en;

            if (rd_en)
                pending_addr <= rd_addr;
        end
    end

    // Monitor dos enderecos solicitados
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

    task automatic run_lookup(input logic [15:0] test_hash);
        logic [20:0] test_base;
        integer j;

        begin
            test_base = {1'b0, test_hash, 4'b0000};

            // Aguarda o controlador estar em IDLE
            @(negedge clk);
            while (dut.state != dut.IDLE)
                @(negedge clk);

            // Prepara cinco palavras de teste
            expected_base = test_base;
            reads_seen = 0;

            for (j = 0; j < 5; j = j + 1)
                memory[test_base + j] = 32'hA0000000 + j;

            hash_index    = test_hash;
            flow_key      = 104'h123456789ABCDEF123456789AB;
            packet_length = 16'd128;
            timestamp     = 80'd1234;
            hash_valid    = 1'b1;

            @(negedge clk);
            hash_valid = 1'b0;

            // Aguarda o lookup terminar
            wait (dut.state == dut.LOOKUP_DONE);
            @(negedge clk);

            // Verifica as cinco palavras recebidas
            for (j = 0; j < 5; j = j + 1) begin
                if (flow_entry[j*32 +: 32] !==
                    (32'hA0000000 + j)) begin
                    $error(
                        "Palavra W%0d incorreta: esperado=%h, recebido=%h",
                        j,
                        32'hA0000000 + j,
                        flow_entry[j*32 +: 32]
                    );
                    errors = errors + 1;
                end
            end

            // Verifica que os bits restantes continuam zerados
            if (flow_entry[383:160] !== 224'b0) begin
                $error("Os bits [383:160] deveriam permanecer zerados.");
                errors = errors + 1;
            end

            if (reads_seen != 5) begin
                $error(
                    "Quantidade incorreta de leituras: %0d",
                    reads_seen
                );
                errors = errors + 1;
            end

            if (errors == 0)
                $display(
                    "PASSOU: hash_index=%0d, base=%0d, leituras=%0d",
                    test_hash,
                    test_base,
                    reads_seen
                );

            @(negedge clk);
        end
    endtask

    initial begin
        reset         = 1'b1;
        hash_index    = 16'b0;
        flow_key      = 104'b0;
        packet_length = 16'b0;
        timestamp     = 80'b0;
        hash_valid    = 1'b0;

        rd_data       = 32'b0;
        rd_valid      = 1'b0;

        errors        = 0;
        reads_seen    = 0;
        expected_base = 21'b0;

        pending_read  = 1'b0;
        pending_addr  = 21'b0;

        for (i = 0; i < 4096; i = i + 1)
            memory[i] = 32'b0;

        repeat (3) @(negedge clk);
        reset = 1'b0;

        run_lookup(16'd0);
        run_lookup(16'd5);
        run_lookup(16'd100);

        if (errors == 0)
            $display("TODOS OS TESTES PASSARAM!");
        else
            $display("TESTE FINALIZADO COM %0d ERRO(S).", errors);

        #20;
        $finish;
    end

    // Timeout de seguranca
    initial begin
        #100000;
        $fatal(1, "TIMEOUT: o lookup nao terminou.");
    end

endmodule
