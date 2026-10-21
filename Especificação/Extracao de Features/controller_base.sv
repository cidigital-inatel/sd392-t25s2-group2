`timescale 1ns/1ps

// Controller da Flow Table.
// Reset sincrono, ativo em nivel alto.
// Protocolo de entrada (valid, sem ready), conforme o padrao do emissor/receptor:
//   - captura os dados somente em IDLE, quando hash_valid = 1 (start)
//   - uma nova captura so e aceita depois que hash_valid voltar a 0
//     (estado WAIT_VALID_LOW)
module controller (
    input  logic         clk,
    input  logic         rst,

    // Barramento de entrada (protocolo valid, sem ready)
    input  logic [15:0]  hash_index,
    input  logic [103:0] flow_key,
    input  logic [15:0]  packet_length,
    input  logic [79:0]  timestamp,
    input  logic         hash_valid,

    // Flow Table
    output logic         rd_en,
    output logic [19:0]  rd_addr,
    input  logic [31:0]  rd_data,
    input  logic         rd_valid,

    output logic         wr_en,
    output logic [19:0]  wr_addr,
    output logic [31:0]  wr_data,
    input  logic         wr_done,

    // Flow Finalizer (reservado para a proxima etapa)
    output logic [415:0] flow_entry,
    output logic         fin_valid,
    input  logic         fin_done,

    // Resultado do lookup
    output logic [1:0]   lookup_result,
    output logic         lookup_done
);

    localparam logic [1:0] RESULT_NONE      = 2'b00;
    localparam logic [1:0] RESULT_MISS      = 2'b01;
    localparam logic [1:0] RESULT_HIT       = 2'b10;
    localparam logic [1:0] RESULT_COLLISION = 2'b11;

    typedef enum logic [3:0] {
        IDLE,             // Aguarda hash_valid e captura os dados
        LOOKUP_REQ,
        LOOKUP_WAIT,
        CLASSIFY,
        HIT_READ_REQ,
        HIT_READ_WAIT,
        PREPARE_WRITE,
        WRITE_REQ,
        WRITE_WAIT,
        WAIT_VALID_LOW    // Aguarda hash_valid voltar a zero
    } state_t;

    state_t state;

    logic [103:0] flow_key_reg;
    logic [15:0]  packet_length_reg;
    logic [79:0]  timestamp_reg;

    logic [19:0]  base_addr;
    logic [3:0]   word_index;
    logic [3:0]   write_word_index;

    logic         stored_valid;
    logic [103:0] stored_flow_key;

    logic [31:0]  packet_count_reg;
    logic [31:0]  byte_count_reg;

    wire is_miss = (lookup_result == RESULT_MISS);

    // start: pulso de 1 ciclo. So existe em IDLE com hash_valid = 1,
    // logo um hash_valid fora de IDLE nunca e capturado.
    wire start = (state == IDLE) && hash_valid;

    // Esta etapa nao usa a finalizacao por pacote.
    assign fin_valid = 1'b0;

    // ------------------------------------------------------------
    // Recepcao: captura os dados quando start = 1
    // ------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            base_addr         <= '0;
            flow_key_reg      <= '0;
            packet_length_reg <= '0;
            timestamp_reg     <= '0;
        end else if (start) begin
            base_addr         <= {hash_index, 4'b0000};   // hash_index x 16
            flow_key_reg      <= flow_key;
            packet_length_reg <= packet_length;
            timestamp_reg     <= timestamp;
        end
    end

    // ------------------------------------------------------------
    // Interface combinacional com a Flow Table
    // ------------------------------------------------------------
    always_comb begin
        rd_en   = 1'b0;
        rd_addr = {base_addr[19:4], word_index};
        wr_en   = 1'b0;
        wr_addr = {base_addr[19:4], write_word_index};
        wr_data = 32'b0;

        case (state)
            LOOKUP_REQ, HIT_READ_REQ: rd_en = 1'b1;

            WRITE_REQ: begin
                wr_en = 1'b1;

                case (write_word_index)
                    4'd0:  wr_data = 32'h00000001;
                    4'd1:  wr_data = flow_key_reg[31:0];
                    4'd2:  wr_data = flow_key_reg[63:32];
                    4'd3:  wr_data = flow_key_reg[95:64];
                    4'd4:  wr_data = {24'b0, flow_key_reg[103:96]};

                    4'd5:  wr_data = is_miss ? 32'd1
                                             : packet_count_reg + 32'd1;
                    4'd6:  wr_data = is_miss ? {16'b0, packet_length_reg}
                                             : byte_count_reg + {16'b0, packet_length_reg};

                    4'd7:  wr_data = timestamp_reg[31:0];
                    4'd8:  wr_data = timestamp_reg[63:32];
                    4'd9:  wr_data = {16'b0, timestamp_reg[79:64]};

                    4'd10: wr_data = timestamp_reg[31:0];
                    4'd11: wr_data = timestamp_reg[63:32];
                    4'd12: wr_data = {16'b0, timestamp_reg[79:64]};

                    default: wr_data = 32'b0;
                endcase
            end

            default: ;
        endcase
    end

    // ------------------------------------------------------------
    // FSM
    // ------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            state            <= IDLE;
            word_index       <= '0;
            write_word_index <= '0;
            stored_valid     <= 1'b0;
            stored_flow_key  <= '0;
            packet_count_reg <= '0;
            byte_count_reg   <= '0;
            flow_entry       <= '0;
            lookup_result    <= RESULT_NONE;
            lookup_done      <= 1'b0;
        end else begin
            lookup_done <= 1'b0;

            case (state)

                IDLE: begin
                    if (start) begin
                        word_index      <= 4'd0;
                        flow_entry      <= '0;
                        stored_valid    <= 1'b0;
                        stored_flow_key <= '0;
                        lookup_result   <= RESULT_NONE;
                        state           <= LOOKUP_REQ;
                    end
                end

                // Lookup: le W0..W4 (valid + flow_key)
                LOOKUP_REQ: state <= LOOKUP_WAIT;

                LOOKUP_WAIT: begin
                    if (rd_valid) begin
                        case (word_index)
                            4'd0: begin
                                stored_valid     <= rd_data[0];   // so o bit 0
                                flow_entry[31:0] <= rd_data;
                            end
                            4'd1: begin
                                stored_flow_key[31:0] <= rd_data;
                                flow_entry[63:32]     <= rd_data;
                            end
                            4'd2: begin
                                stored_flow_key[63:32] <= rd_data;
                                flow_entry[95:64]      <= rd_data;
                            end
                            4'd3: begin
                                stored_flow_key[95:64] <= rd_data;
                                flow_entry[127:96]     <= rd_data;
                            end
                            4'd4: begin
                                stored_flow_key[103:96] <= rd_data[7:0]; // mascara W4
                                flow_entry[159:128]     <= rd_data;
                            end
                            default: ;
                        endcase

                        if (word_index == 4'd4) begin
                            state <= CLASSIFY;
                        end else begin
                            word_index <= word_index + 1'b1;
                            state      <= LOOKUP_REQ;
                        end
                    end
                end

                // Classificacao: MISS / HIT / COLLISION
                CLASSIFY: begin
                    if (!stored_valid) begin
                        lookup_result <= RESULT_MISS;

                        flow_entry[31:0]    <= 32'h00000001;
                        flow_entry[63:32]   <= flow_key_reg[31:0];
                        flow_entry[95:64]   <= flow_key_reg[63:32];
                        flow_entry[127:96]  <= flow_key_reg[95:64];
                        flow_entry[159:128] <= {24'b0, flow_key_reg[103:96]};
                        flow_entry[191:160] <= 32'd1;
                        flow_entry[223:192] <= {16'b0, packet_length_reg};
                        flow_entry[255:224] <= timestamp_reg[31:0];
                        flow_entry[287:256] <= timestamp_reg[63:32];
                        flow_entry[319:288] <= {16'b0, timestamp_reg[79:64]};
                        flow_entry[351:320] <= timestamp_reg[31:0];
                        flow_entry[383:352] <= timestamp_reg[63:32];
                        flow_entry[415:384] <= {16'b0, timestamp_reg[79:64]};

                        write_word_index <= 4'd0;
                        state            <= PREPARE_WRITE;

                    end else if (stored_flow_key == flow_key_reg) begin
                        lookup_result <= RESULT_HIT;
                        word_index    <= 4'd5;
                        state         <= HIT_READ_REQ;

                    end else begin
                        // COLLISION: nenhuma escrita, entrada preservada
                        lookup_result <= RESULT_COLLISION;
                        lookup_done   <= 1'b1;
                        state         <= WAIT_VALID_LOW;
                    end
                end

                // HIT: le W5 e W6
                HIT_READ_REQ: state <= HIT_READ_WAIT;

                HIT_READ_WAIT: begin
                    if (rd_valid) begin
                        if (word_index == 4'd5) begin
                            packet_count_reg    <= rd_data;
                            flow_entry[191:160] <= rd_data;
                            word_index          <= 4'd6;
                            state               <= HIT_READ_REQ;
                        end else begin
                            byte_count_reg      <= rd_data;
                            flow_entry[223:192] <= rd_data;
                            state               <= PREPARE_WRITE;
                        end
                    end
                end

                PREPARE_WRITE: begin
                    if (is_miss) begin
                        write_word_index <= 4'd0;
                    end else begin
                        flow_entry[191:160] <= packet_count_reg + 32'd1;
                        flow_entry[223:192] <= byte_count_reg + {16'b0, packet_length_reg};
                        flow_entry[351:320] <= timestamp_reg[31:0];
                        flow_entry[383:352] <= timestamp_reg[63:32];
                        flow_entry[415:384] <= {16'b0, timestamp_reg[79:64]};
                        write_word_index    <= 4'd5;
                    end
                    state <= WRITE_REQ;
                end

                // Escritas: MISS = W0..W12 (13); HIT = W5, W6, W10, W11, W12 (5)
                WRITE_REQ: state <= WRITE_WAIT;

                WRITE_WAIT: begin
                    if (wr_done) begin
                        if (write_word_index == 4'd12) begin
                            lookup_done <= 1'b1;
                            state       <= WAIT_VALID_LOW;
                        end else begin
                            state <= WRITE_REQ;
                            if (is_miss)
                                write_word_index <= write_word_index + 1'b1;
                            else if (write_word_index == 4'd6)
                                write_word_index <= 4'd10;
                            else
                                write_word_index <= write_word_index + 1'b1;
                        end
                    end
                end

                // Impede nova captura enquanto hash_valid permanecer alto
                WAIT_VALID_LOW: begin
                    if (!hash_valid)
                        state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule