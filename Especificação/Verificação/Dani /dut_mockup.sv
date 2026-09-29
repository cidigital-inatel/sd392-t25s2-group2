// Recebe uma interface AXI4-Stream simplificada (TDATA/TKEEP/TVALID/TLAST/
// TUSER) e apenas contabiliza pacotes e bytes recebidos. Gera TREADY com um
// padrao deterministico de backpressure, para forcar o testbench a provar
// que mantem os sinais estaveis enquanto TREADY estiver baixo.

module dut_mockup #(
    parameter int DATA_WIDTH = 64,
    parameter int KEEP_WIDTH = DATA_WIDTH/8
) (
    input  logic                    clk,
    input  logic                    rst_n,       // reset ativo em nivel baixo (alinhado ao aresetn do MAC)
    input  logic                    tvalid,
    output logic                    tready,
    input  logic [DATA_WIDTH-1:0]   tdata,
    input  logic [KEEP_WIDTH-1:0]   tkeep,
    input  logic                    tlast,
    input  logic                    tuser,
    output logic [31:0]             total_packets,
    output logic [31:0]             total_bytes,
    output logic [31:0]             invalid_frames
);

    // ---------------------------------------------------------------
    // Geracao de TREADY: padrao fixo de backpressure (nao e o
    // comportamento do MAC real, que nao possui TREADY -- serve aqui
    // apenas para validar que o testbench segura os dados corretamente
    // enquanto TREADY estiver baixo).
    // ---------------------------------------------------------------
    logic [2:0] stall_cnt;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            stall_cnt <= '0;
        else
            stall_cnt <= stall_cnt + 3'd1;
    end

    assign tready = !(stall_cnt == 3'd4 || stall_cnt == 3'd5);

    // ---------------------------------------------------------------
    // Contadores
    // ---------------------------------------------------------------
    logic frame_has_error;

    function automatic int popcount8(input logic [KEEP_WIDTH-1:0] v);
        int c;
        begin
            c = 0;
            for (int i = 0; i < KEEP_WIDTH; i++)
                if (v[i]) c++;
            popcount8 = c;
        end
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            total_packets   <= '0;
            total_bytes     <= '0;
            invalid_frames  <= '0;
            frame_has_error <= 1'b0;
        end else begin
            if (tvalid && tready) begin
                total_bytes <= total_bytes + popcount8(tkeep);
                if (!tuser)
                    frame_has_error <= 1'b1;
                if (tlast) begin
                    total_packets <= total_packets + 32'd1;
                    if (frame_has_error || !tuser)
                        invalid_frames <= invalid_frames + 32'd1;
                    frame_has_error <= 1'b0;
                end
            end
        end
    end

endmodule
