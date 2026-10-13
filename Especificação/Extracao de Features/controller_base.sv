
module controller (
    input  logic         clk,
    input  logic         reset,

    input  logic [15:0]  hash_index,
    input  logic [103:0] flow_key,
    input  logic [15:0]  packet_length,
    input  logic [79:0]  timestamp,
    input  logic         hash_valid,

    output logic         rd_en,
    output logic [20:0]  rd_addr,
    input  logic [31:0]  rd_data,
    input  logic         rd_valid,

    output logic [383:0] flow_entry
);

    typedef enum logic [1:0] {
        IDLE,
        LOOKUP_REQ,
        LOOKUP_WAIT,
        LOOKUP_DONE
    } state_t;

    state_t state;

    logic [15:0]  hash_index_reg;
    logic [103:0] flow_key_reg;
    logic [15:0]  packet_length_reg;
    logic [79:0]  timestamp_reg;

    logic         start;
    logic [20:0]  base_addr;
    logic [2:0]   word_index;

    // Captura dos metadados e geracao de start
    always_ff @(posedge clk) begin
        if (reset) begin
            hash_index_reg    <= '0;
            flow_key_reg      <= '0;
            packet_length_reg <= '0;
            timestamp_reg     <= '0;
            start             <= 1'b0;
        end else begin
            if (hash_valid) begin
                hash_index_reg    <= hash_index;
                flow_key_reg      <= flow_key;
                packet_length_reg <= packet_length;
                timestamp_reg     <= timestamp;

                start <= 1'b1;
            end else if (start) begin
                start <= 1'b0;
            end
        end
    end

    // Solicitacao de leitura
    always_comb begin
        rd_en   = 1'b0;
        rd_addr = '0;

        if (state == LOOKUP_REQ) begin
            rd_en   = 1'b1;
            rd_addr = base_addr + word_index;
        end
    end

    // FSM do LOOKUP
    always_ff @(posedge clk) begin
        if (reset) begin
            state      <= IDLE;
            base_addr  <= '0;
            word_index <= '0;
            flow_entry <= '0;
        end else begin
            case (state)

                IDLE: begin
                    word_index <= '0;

                    if (start) begin
                        base_addr  <= {1'b0, hash_index_reg, 4'b0000};
                        flow_entry <= '0;
                        state      <= LOOKUP_REQ;
                    end
                end

                LOOKUP_REQ: begin
                    state <= LOOKUP_WAIT;
                end

                LOOKUP_WAIT: begin
                    if (rd_valid) begin
                        flow_entry[word_index * 32 +: 32] <= rd_data;

                        if (word_index == 3'd4) begin
                            state <= LOOKUP_DONE;
                        end else begin
                            word_index <= word_index + 1'b1;
                            state      <= LOOKUP_REQ;
                        end
                    end
                end

                LOOKUP_DONE: begin
                    state      <= IDLE;
                    word_index <= '0;
                end

                default: begin
                    state      <= IDLE;
                    word_index <= '0;
                end

            endcase
        end
    end

endmodule
