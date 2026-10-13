// flow_table_tb.sv
`timescale 1ns/1ps

module flow_table_tb;

    localparam int ADDR_WIDTH = 20;
    localparam int DATA_WIDTH = 32;

    logic clk = 1'b0;
    logic rst;

    logic                  rd_en;
    logic [ADDR_WIDTH-1:0] rd_addr;
    logic [DATA_WIDTH-1:0] rd_data;
    logic                  rd_valid;

    logic                  wr_en;
    logic [ADDR_WIDTH-1:0] wr_addr;
    logic [DATA_WIDTH-1:0] wr_data;
    logic                  wr_done;

    flow_table #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .rd_en(rd_en),
        .rd_addr(rd_addr),
        .rd_data(rd_data),
        .rd_valid(rd_valid),
        .wr_en(wr_en),
        .wr_addr(wr_addr),
        .wr_data(wr_data),
        .wr_done(wr_done)
    );

    always #5 clk = ~clk;

    // Escreve uma palavra e verifica o pulso de conclusao.
    task automatic write_word(
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [DATA_WIDTH-1:0] data
    );
        @(negedge clk);
        wr_en   = 1'b1;
        wr_addr = addr;
        wr_data = data;
        rd_en   = 1'b0;

        @(posedge clk);
        #1;
        if (wr_done !== 1'b1)
            $fatal(1, "ERRO: wr_done nao foi ativado para endereco %0d", addr);

        @(negedge clk);
        wr_en = 1'b0;

        @(posedge clk);
        #1;
        if (wr_done !== 1'b0)
            $fatal(1, "ERRO: wr_done deveria voltar a zero");
    endtask

    // Le uma palavra e compara o dado recebido com o esperado.
    task automatic read_and_check(
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [DATA_WIDTH-1:0] expected
    );
        @(negedge clk);
        rd_en   = 1'b1;
        rd_addr = addr;
        wr_en   = 1'b0;

        @(posedge clk);
        #1;
        if (rd_valid !== 1'b1)
            $fatal(1, "ERRO: rd_valid nao foi ativado para endereco %0d", addr);

        if (rd_data !== expected)
            $fatal(1,
                "ERRO: endereco %0d: esperado 0x%08h, recebido 0x%08h",
                addr, expected, rd_data
            );

        @(negedge clk);
        rd_en = 1'b0;

        @(posedge clk);
        #1;
        if (rd_valid !== 1'b0)
            $fatal(1, "ERRO: rd_valid deveria voltar a zero");
    endtask

    initial begin
        rst     = 1'b1;
        rd_en   = 1'b0;
        rd_addr = '0;
        wr_en   = 1'b0;
        wr_addr = '0;
        wr_data = '0;

        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        $display("Teste: escrita e leitura de uma palavra");
        write_word(20'd80, 32'h1234_ABCD);
        read_and_check(20'd80, 32'h1234_ABCD);

        $display("Teste 2: sobrescrita de uma palavra");
        write_word(20'd81, 32'hDEAD_BEEF);
        read_and_check(20'd81, 32'hDEAD_BEEF);

        $display("Fim.");
        $finish;
    end

endmodule