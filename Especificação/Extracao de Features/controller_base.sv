
module controller (
    // Clock and reset
    input  logic         clk,
    input  logic         reset_n,

    // Packet metadata
    input  logic [103:0] flow_key,
    input  logic [15:0]  hash_index,
    input  logic [15:0]  packet_length,
    input  logic [79:0]  timestamp,
    input  logic         in_valid,
    output logic         in_ready,

    // PCAP and system control
    input  logic         pcap_done,
    input  logic         ctrl_restart,
    output logic         all_flows_done,

    // Flow Table read interface
    input  logic [31:0]  rd_data,
    input  logic         rd_valid,
    output logic         rd_en,
    output logic [19:0]  rd_addr,

    // Flow Table write interface
    input  logic         wr_done,
    output logic         wr_en,
    output logic [19:0]  wr_addr,
    output logic [31:0]  wr_data,

    // Flow Finalizer interface
    input  logic         finalizer_ready,
    input  logic         finalizer_done,
    output logic         fin_en,
    output logic         finalizer_valid,

    // Flow entry
    output logic [511:0] flow_entry,

    // Collision reporting
    output logic         collision_event,
    output logic [31:0]  collision_count
);

    // =====================================================
    // Flow Table configuration
    // 65,536 entries x 16 words x 32 bits
    // Base address = hash_index * 16
    // =====================================================

    localparam logic [2:0] LOOKUP_LAST_WORD = 3'd4;

    typedef enum logic [1:0] {
        IDLE,
        LOOKUP_REQ,
        LOOKUP_WAIT,
        LOOKUP_DONE
    } state_t;

    state_t state;

    logic [15:0] hash_index_reg;
    logic [103:0] flow_key_reg;
    logic [15:0] packet_length_reg;
    logic [79:0] timestamp_reg;

    logic [19:0] base_addr;
    logic [2:0]  word_index;

    // =====================================================
    // Combinational outputs
    // =====================================================

    always_comb begin
        in_ready = 1'b0;

        rd_en   = 1'b0;
        rd_addr = 20'd0;

        wr_en   = 1'b0;
        wr_addr = 20'd0;
        wr_data = 32'd0;

        fin_en         = 1'b0;
        finalizer_valid = 1'b0;

        all_flows_done = 1'b0;
        collision_event = 1'b0;
        collision_count = 32'd0;

        case (state)

            IDLE: begin
                in_ready = 1'b1;
            end

            LOOKUP_REQ: begin
                rd_en   = 1'b1;
                rd_addr = base_addr + word_index;
            end

            default: begin
                // No request in other states
            end

        endcase
    end

    // =====================================================
    // Capture packet metadata and calculate base address
    // =====================================================

    always_ff @(posedge clk) begin
        if (!reset_n) begin
            hash_index_reg    <= 16'd0;
            flow_key_reg      <= 104'd0;
            packet_length_reg <= 16'd0;
            timestamp_reg     <= 80'd0;
            base_addr         <= 20'd0;
        end
        else if (state == IDLE && in_valid && in_ready) begin
            hash_index_reg    <= hash_index;
            flow_key_reg      <= flow_key;
            packet_length_reg <= packet_length;
            timestamp_reg     <= timestamp;

            // Equivalent to hash_index * 16
            base_addr <= {hash_index, 4'b0000};
        end
    end

    // =====================================================
    // Lookup state machine
    // =====================================================

    always_ff @(posedge clk) begin
        if (!reset_n) begin
            state      <= IDLE;
            word_index <= 3'd0;
            flow_entry <= 512'd0;
        end
        else begin
            case (state)

                IDLE: begin
                    word_index <= 3'd0;

                    if (in_valid && in_ready) begin
                        state <= LOOKUP_REQ;
                    end
                end

                LOOKUP_REQ: begin
                    // rd_en and rd_addr are asserted
                    // by the combinational logic.
                    state <= LOOKUP_WAIT;
                end

                LOOKUP_WAIT: begin
                    if (rd_valid) begin
                        // Store each 32-bit word in flow_entry.
                        flow_entry[word_index * 32 +: 32]
                            <= rd_data;

                        if (word_index == LOOKUP_LAST_WORD) begin
                            state <= LOOKUP_DONE;
                        end
                        else begin
                            word_index <= word_index + 1'b1;
                            state <= LOOKUP_REQ;
                        end
                    end
                end

                LOOKUP_DONE: begin
                    // Lookup is complete.
                    // MISS/HIT/COLLISION processing will
                    // be added in the next implementation stage.
                    state <= IDLE;
                    word_index <= 3'd0;
                end

                default: begin
                    state      <= IDLE;
                    word_index <= 3'd0;
                end

            endcase
        end
    end

endmodule
