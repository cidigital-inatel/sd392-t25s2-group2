
`timescale 1ns/1ps

module tb_controller;

    logic clk;
    logic reset_n;

    logic [103:0] flow_key;
    logic [15:0]  hash_index;
    logic [15:0]  packet_length;
    logic [79:0]  timestamp;
    logic         in_valid;
    logic         in_ready;

    logic         pcap_done;
    logic         ctrl_restart;
    logic         all_flows_done;

    logic [31:0]  rd_data;
    logic         rd_valid;
    logic         rd_en;
    logic [19:0]  rd_addr;

    logic         wr_done;
    logic         wr_en;
    logic [19:0]  wr_addr;
    logic [31:0]  wr_data;

    logic         finalizer_ready;
    logic         finalizer_done;
    logic         fin_en;
    logic         finalizer_valid;

    logic [511:0] flow_entry;

    logic         collision_event;
    logic [31:0]  collision_count;

    // -----------------------------------------------------
    // Memory model
    // -----------------------------------------------------

    logic [31:0] memory [0:1048575];

    logic        pending_read;
    logic [19:0] pending_addr;

    integer reads_seen;
    integer errors;
    integer test_number;

    logic [19:0] expected_base;

    // -----------------------------------------------------
    // Clock: period = 10 ns
    // -----------------------------------------------------

    initial clk = 1'b0;
    always #5 clk = ~clk;

    // -----------------------------------------------------
    // DUT
    // -----------------------------------------------------

    controller dut (
        .clk              (clk),
        .reset_n          (reset_n),

        .flow_key         (flow_key),
        .hash_index       (hash_index),
        .packet_length    (packet_length),
        .timestamp        (timestamp),
        .in_valid         (in_valid),
        .in_ready         (in_ready),

        .pcap_done        (pcap_done),
        .ctrl_restart     (ctrl_restart),
        .all_flows_done   (all_flows_done),

        .rd_data          (rd_data),
        .rd_valid         (rd_valid),
        .rd_en            (rd_en),
        .rd_addr          (rd_addr),

        .wr_done          (wr_done),
        .wr_en            (wr_en),
        .wr_addr          (wr_addr),
        .wr_data          (wr_data),

        .finalizer_ready  (finalizer_ready),
        .finalizer_done   (finalizer_done),
        .fin_en           (fin_en),
        .finalizer_valid  (finalizer_valid),

        .flow_entry       (flow_entry),

        .collision_event  (collision_event),
        .collision_count  (collision_count)
    );

    // -----------------------------------------------------
    // Synchronous read memory model
    //
    // A request sampled at a rising edge returns data
    // and asserts rd_valid at the following rising edge.
    // -----------------------------------------------------

    always_ff @(posedge clk) begin
        if (!reset_n) begin
            rd_data      <= 32'd0;
            rd_valid     <= 1'b0;
            pending_read <= 1'b0;
            pending_addr <= 20'd0;
        end
        else begin
            rd_valid <= pending_read;

            if (pending_read)
                rd_data <= memory[pending_addr];

            pending_read <= rd_en;

            if (rd_en)
                pending_addr <= rd_addr;
        end
    end

    // -----------------------------------------------------
    // Monitor read requests and check their addresses
    // -----------------------------------------------------

    always @(posedge clk) begin
        if (!reset_n) begin
            reads_seen <= 0;
        end
        else if (rd_en) begin
            if (rd_addr !== (expected_base + reads_seen)) begin
                $error(
                    "Endereco incorreto: esperado=%0d, recebido=%0d",
                    expected_base + reads_seen,
                    rd_addr
                );
                errors = errors + 1;
            end

            if (wr_en !== 1'b0) begin
                $error("wr_en deveria permanecer em zero no lookup");
                errors = errors + 1;
            end

            reads_seen <= reads_seen + 1;
        end
    end

    // -----------------------------------------------------
    // Test one lookup
    // -----------------------------------------------------

    task automatic run_lookup(
        input logic [15:0]  test_hash,
        input logic [103:0] test_key,
        input logic [15:0]  test_length,
        input logic [79:0]  test_timestamp
    );

        logic [19:0] calculated_base;
        integer k;

        begin
            calculated_base = {test_hash, 4'b0000};

            // Wait until the controller is ready for a packet.
            @(negedge clk);
            while (in_ready !== 1'b1)
                @(negedge clk);

            expected_base = calculated_base;
            reads_seen = 0;

            // Prepare five memory words with known data.
            for (k = 0; k < 5; k = k + 1)
                memory[calculated_base + k] =
                    32'hA0000000 + k;

            flow_key      = test_key;
            hash_index    = test_hash;
            packet_length = test_length;
            timestamp     = test_timestamp;

            in_valid = 1'b1;

            // Input is accepted on a rising edge.
            @(negedge clk);
            in_valid = 1'b0;

            // Wait for all five read requests.
            wait (reads_seen == 5);

            // Wait until all five returned words have been stored.
            wait (dut.state == dut.LOOKUP_DONE);
            @(negedge clk);

            // Verify the five words.
            for (k = 0; k < 5; k = k + 1) begin
                if (flow_entry[k*32 +: 32] !==
                    (32'hA0000000 + k)) begin

                    $error(
                        "Teste %0d: W%0d incorreta. Esperado=%h, recebido=%h",
                        test_number,
                        k,
                        32'hA0000000 + k,
                        flow_entry[k*32 +: 32]
                    );

                    errors = errors + 1;
                end
            end

            // Verify unused upper bits remain zero.
            if (flow_entry[511:160] !== 352'd0) begin
                $error(
                    "Teste %0d: os bits superiores de flow_entry deveriam ser zero",
                    test_number
                );
                errors = errors + 1;
            end

            if (reads_seen != 5) begin
                $error(
                    "Teste %0d: quantidade de leituras incorreta: %0d",
                    test_number,
                    reads_seen
                );
                errors = errors + 1;
            end

            if (wr_en !== 1'b0) begin
                $error(
                    "Teste %0d: ocorreu escrita inesperada",
                    test_number
                );
                errors = errors + 1;
            end

            if (errors == 0) begin
                $display(
                    "Teste %0d passou: hash=%0d, base=%0d, leituras=%0d",
                    test_number,
                    test_hash,
                    calculated_base,
                    reads_seen
                );
            end
            else begin
                $display(
                    "Teste %0d terminou com erros acumulados: %0d",
                    test_number,
                    errors
                );
            end

            // Allow the FSM to return to IDLE.
            @(negedge clk);
            while (in_ready !== 1'b1)
                @(negedge clk);
        end
    endtask

    // -----------------------------------------------------
    // Main test sequence
    // -----------------------------------------------------

    initial begin
        reset_n = 1'b0;

        flow_key      = '0;
        hash_index    = '0;
        packet_length = '0;
        timestamp     = '0;
        in_valid      = 1'b0;

        pcap_done       = 1'b0;
        ctrl_restart    = 1'b0;
        wr_done         = 1'b0;
        finalizer_ready = 1'b0;
        finalizer_done  = 1'b0;

        expected_base = '0;
        reads_seen = 0;
        errors = 0;
        test_number = 0;

        // Initialize the small subset of memory used by tests.
        // The model has the full address range, but only these
        // locations are initialized with test data.
        repeat (3) @(negedge clk);
        reset_n = 1'b1;

        // Test 1: hash = 0, base address = 0
        test_number = 1;
        run_lookup(
            16'd0,
            104'h00000000000000000000000001,
            16'd64,
            80'd1001
        );

        // Test 2: hash = 5, base address = 80
        test_number = 2;
        run_lookup(
            16'd5,
            104'h123456789ABCDEF123456789AB,
            16'd128,
            80'd1234
        );

        // Test 3: hash = 100, base address = 1600
        test_number = 3;
        run_lookup(
            16'd100,
            104'h00000000000000000000000064,
            16'd256,
            80'd5678
        );

        if (errors == 0)
            $display("PASSOU: todos os testes foram concluidos sem erros.");
        else
            $display("FALHOU: total de erros = %0d", errors);

        #20;
        $finish;
    end

    // -----------------------------------------------------
    // Global timeout
    // -----------------------------------------------------

    initial begin
        #100000;
        $fatal(1, "Timeout: a simulacao excedeu o tempo limite.");
    end

endmodule
