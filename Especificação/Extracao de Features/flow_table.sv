// flow_table.sv
// Memoria comportamental da Flow Table: 65.536 entradas x 16 palavras x 32 bits.
// A memoria nao inicializa seu conteudo.
// Leitura sincrona: rd_valid fica ativo no ciclo seguinte ao pedido.
// Escrita: wr_done fica ativo no ciclo seguinte ao pedido.

module flow_table #(
    parameter int ADDR_WIDTH = 20,
    parameter int DATA_WIDTH = 32,
    parameter int DEPTH      = (1 << ADDR_WIDTH)
) (
    input  logic                  clk,
    input  logic                  rst,

    input  logic                  rd_en,
    input  logic [ADDR_WIDTH-1:0] rd_addr,
    output logic [DATA_WIDTH-1:0] rd_data,
    output logic                  rd_valid,

    input  logic                  wr_en,
    input  logic [ADDR_WIDTH-1:0] wr_addr,
    input  logic [DATA_WIDTH-1:0] wr_data,
    output logic                  wr_done
);

    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // O reset limpa apenas os sinais de controle; nao apaga toda a memoria.
    always_ff @(posedge clk) begin
        if (rst) begin
            rd_data  <= '0;
            rd_valid <= 1'b0;
            wr_done  <= 1'b0;
        end else begin
            rd_valid <= rd_en;
            wr_done  <= wr_en;

            if (rd_en) begin
                rd_data <= mem[rd_addr];
            end

            if (wr_en) begin
                mem[wr_addr] <= wr_data;
            end
        end
    end

endmodule