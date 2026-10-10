module controller (
    input  wire         clk,
    input  wire         reset,

    input  wire [15:0]  hash_index,
    input  wire [103:0] flow_key,
    input  wire [15:0]  packet_length,
    input  wire [79:0]  timestamp,
    input  wire         hash_valid,

    input  wire [15:0]  rd_data,
    input  wire         rd_valid,
    input  wire         wr_done,
    input  wire         fin_done,

    output reg          rd_en,
    output reg  [20:0]  rd_addr,

    output reg          wr_en,
    output reg  [20:0]  wr_addr,
    output reg  [15:0]  wr_data,

    output reg  [383:0] flow_entry,
    output reg          fin_valid
);

    localparam [4:0]  WORDS_PER_ENTRY = 5'd24;
    localparam [20:0] WORDS_21        = 21'd24;

    // Estados da FSM
    localparam [2:0] IDLE        = 3'd0;
    localparam [2:0] LOOKUP_REQ  = 3'd1;
    localparam [2:0] LOOKUP_WAIT = 3'd2;
    localparam [2:0] LOOKUP_DONE = 3'd3;

    reg [2:0] state;

    reg start;

    reg [15:0]  hash_index_reg;
    reg [103:0] flow_key_reg;
    reg [15:0]  packet_length_reg;
    reg [79:0]  timestamp_reg;

    reg [20:0] base_addr;
    reg [4:0]  word_index;

    // Interface com a Flow Table.
    // Nesta etapa, apenas as leituras sao implementadas.
    always @(*) begin
        rd_en   = 1'b0;
        rd_addr = 21'd0;

        wr_en   = 1'b0;
        wr_addr = 21'd0;
        wr_data = 16'd0;

        fin_valid = 1'b0;

        if (state == LOOKUP_REQ) begin
            rd_en   = 1'b1;
            rd_addr = base_addr + word_index;
        end
    end

    // Captura dos metadados e geracao do sinal start.
    always @(posedge clk) begin
        if (reset) begin
            hash_index_reg    <= 16'd0;
            flow_key_reg      <= 104'd0;
            packet_length_reg <= 16'd0;
            timestamp_reg     <= 80'd0;
            base_addr         <= 21'd0;
            start             <= 1'b0;
        end else begin
            if (hash_valid) begin
                hash_index_reg    <= hash_index;
                flow_key_reg      <= flow_key;
                packet_length_reg <= packet_length;
                timestamp_reg     <= timestamp;

                // Cada entrada ocupa 24 palavras de 16 bits.
                base_addr <= {5'd0, hash_index} * WORDS_21;

                start <= 1'b1;
            end else if (start) begin
                start <= 1'b0;
            end
        end
    end

    // FSM para solicitar e receber as palavras da Flow Table.
    always @(posedge clk) begin
        if (reset) begin
            state      <= IDLE;
            word_index <= 5'd0;
            flow_entry <= 384'd0;
        end else begin
            case (state)

                IDLE: begin
                    word_index <= 5'd0;

                    if (start)
                        state <= LOOKUP_REQ;
                end

                LOOKUP_REQ: begin
                    // rd_en e rd_addr ficam ativos neste estado.
                    state <= LOOKUP_WAIT;
                end

                LOOKUP_WAIT: begin
                    if (rd_valid) begin
                        flow_entry[word_index*16 +: 16] <= rd_data;

                        if (word_index == WORDS_PER_ENTRY - 5'd1) begin
                            state <= LOOKUP_DONE;
                        end else begin
                            word_index <= word_index + 5'd1;
                            state      <= LOOKUP_REQ;
                        end
                    end
                end

                LOOKUP_DONE: begin
                    state <= IDLE;
                end

                default: begin
                    state <= IDLE;
                end

            endcase
        end
    end

endmodule