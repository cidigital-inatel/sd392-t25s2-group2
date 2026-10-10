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

    // Memoria simulada (so os enderecos 120..143 sao usados)
    reg [15:0] memory [0:4095];

    reg [20:0] pending_addr;
    reg        pending_read;

    integer i;
    integer reads_seen;
    integer errors;

    reg [20:0] expected_base;

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

    // Memoria simulada: retorna os dados um ciclo
    // apos a solicitacao de leitura.
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

    // Verifica os enderecos solicitados pelo Controller.
    always @(posedge clk) begin
        if (reset) begin
            reads_seen <= 0;
        end else if (rd_en) begin
            if (rd_addr !== (expected_base + reads_seen)) begin
                $display("ERRO: Endereco incorreto: obtido=%0d, esperado=%0d",
                         rd_addr, expected_base + reads_seen);
                errors = errors + 1;
            end

            reads_seen <= reads_seen + 1;
        end
    end

    initial begin
        reset         = 1'b1;
        hash_index    = 16'd0;
        flow_key      = 104'd0;
        packet_length = 16'd0;
        timestamp     = 80'd0;
        hash_valid    = 1'b0;

        wr_done       = 1'b0;
        fin_done      = 1'b0;

        reads_seen    = 0;
        errors        = 0;
        expected_base = 21'd120;

        // Inicializa as 24 palavras do registro de teste.
        for (i = 0; i < 24; i = i + 1)
            memory[120 + i] = 16'hA000 + i;

        repeat (3) @(negedge clk);
        reset = 1'b0;

        // Aplica os metadados de um pacote.
        @(negedge clk);

        hash_index    = 16'd5;
        flow_key      = 104'h123456789ABCDEF123456789AB;
        packet_length = 16'd128;
        timestamp     = 80'h1234;
        hash_valid    = 1'b1;

        @(negedge clk);
        hash_valid = 1'b0;

        // Aguarda todas as 24 solicitacoes de leitura.
        wait (reads_seen == 24);
        wait (dut.state == dut.LOOKUP_DONE);

        @(negedge clk);

        // A primeira palavra ocupa os bits [15:0].
        if (flow_entry[15:0] !== 16'hA000) begin
            $display("ERRO: Primeira palavra incorreta: %h", flow_entry[15:0]);
            errors = errors + 1;
        end

        // A ultima palavra ocupa os bits [383:368].
        if (flow_entry[383:368] !== 16'hA017) begin
            $display("ERRO: Ultima palavra incorreta: %h", flow_entry[383:368]);
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("PASSOU: 24 leituras nos enderecos 120 a 143.");
            $display("PASSOU: flow_entry montado corretamente.");
        end else begin
            $display("FALHOU: %0d erro(s) encontrado(s).", errors);
        end

        $finish;
    end

    initial begin
        #10000;
        $display("TIMEOUT: a simulacao nao terminou.");
        $finish;
    end

endmodule