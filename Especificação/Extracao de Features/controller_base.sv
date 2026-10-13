
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

    logic [20:0] base_addr;
    logic [2:0]  word_index;

    always_comb begin
        rd_en   = 1'b0;
        rd_addr = 21'b0;

        case (state)
            LOOKUP_REQ: begin
                rd_en   = 1'b1;
                rd_addr = base_addr + word_index;
            end

            default: begin
                rd_en   = 1'b0;
                rd_addr = 21'b0;
            end
        endcase
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            state      <= IDLE;
            base_addr  <= 21'b0;
            word_index <= 3'b0;
            flow_entry <= 384'b0;
        end else begin
            case (state)

                IDLE: begin
                    word_index <= 3'b0;

                    if (hash_valid) begin
                        base_addr <= {1'b0, hash_index, 4'b0000};
                        flow_entry <= 384'b0;
                        state <= LOOKUP_REQ;
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
                            state <= LOOKUP_REQ;
                        end
                    end
                end

                LOOKUP_DONE: begin
                    state      <= IDLE;
                    word_index <= 3'b0;
                end

                default: begin
                    state      <= IDLE;
                    word_index <= 3'b0;
                end

            endcase
        end
    end

endmodule
