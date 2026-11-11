`timescale 1ns/1ps
`default_nettype none

// Samuel - Hash Unit: valid -> captura atomica -> start registrado -> FSM.
// CRC-16/CCITT-FALSE: poly=1021, init=FFFF, refin/refout=0, xorout=0000.
// Chave de 13 bytes, MSB primeiro. Um registro por vez, sem FIFO.
// Reset SINCRONO ativo alto. start e capture_allowed sao sinais INTERNOS.
// timestamp_in[79:32] = segundos; [31:0] = nanossegundos (passagem integral).
// Semana 6: uma captura por periodo alto de valid; rearmar somente apos baixo.
// Novas transferencias separadas por pelo menos 16 clocks, sem FIFO.
// out_valid dura um ciclo; o consumidor captura na borda em que o observa alto.
module hash_unit (
    input  wire logic         clk,
    input  wire logic         reset,
    input  wire logic [103:0] flow_key_in,
    input  wire logic [15:0]  packet_length_in,
    input  wire logic [79:0]  timestamp_in,
    input  wire logic         in_valid,
    output      logic [15:0]  hash_index_out,
    output      logic [103:0] flow_key_out,
    output      logic [15:0]  packet_length_out,
    output      logic [79:0]  timestamp_out,
    output      logic         out_valid
);
    typedef enum logic [1:0] {IDLE, CALC, RESULT} state_t;
    state_t state;

    logic [103:0] key_reg;
    logic [15:0]  length_reg;
    logic [79:0]  timestamp_reg;
    logic         start;
    logic         capture_allowed;
    logic         valid_seen;
    logic [15:0]  crc_reg;
    logic [15:0]  result_reg;
    logic [3:0]   byte_index;
    logic [7:0]   current_byte;
    logic [15:0]  next_crc;

    function automatic logic [15:0] crc16_next_byte (
        input logic [15:0] crc,
        input logic [7:0]  data_byte
    );
        logic [15:0] value;
        value = crc ^ {data_byte, 8'h00};
        // Oito passos combinacionais, equivalentes a UM byte por clock.
        for (int bit_index = 0; bit_index < 8; bit_index++) begin
            if (value[15])
                value = (value << 1) ^ 16'h1021;
            else
                value = value << 1;
        end
        return value;
    endfunction

    assign capture_allowed  = (state == IDLE) && !start;
    assign current_byte     = key_reg[103 - (int'(byte_index) * 8) -: 8];
    assign next_crc         = crc16_next_byte(crc_reg, current_byte);
    assign hash_index_out   = result_reg;
    assign flow_key_out     = key_reg;
    assign packet_length_out = length_reg;
    assign timestamp_out    = timestamp_reg;
    assign out_valid        = (state == RESULT);

    // Recepcao: preserva juntos os 200 bits e produz start por um ciclo.
    // !start impede sobrescrever a captura enquanto a FSM ainda esta em IDLE.
    always_ff @(posedge clk) begin
        if (reset) begin
            key_reg       <= '0;
            length_reg    <= '0;
            timestamp_reg <= '0;
            start         <= 1'b0;
            valid_seen    <= 1'b0;
        end else begin
            start <= 1'b0;
            // Mesmo apos terminar o calculo, valid alto nao e outro pacote.
            // Registrar o periodo alto inclusive em uma chegada indevida
            // impede aceita-la tardiamente quando o hardware ficar livre.
            if (!in_valid)
                valid_seen <= 1'b0;
            else
                valid_seen <= 1'b1;
            if (in_valid && !valid_seen && capture_allowed) begin
                key_reg       <= flow_key_in;
                length_reg    <= packet_length_in;
                timestamp_reg <= timestamp_in;
                start         <= 1'b1;
            end
        end
    end

    // A FSM usa start da borda ANTERIOR: os dados ja estao capturados.
    always_ff @(posedge clk) begin
        if (reset) begin
            state      <= IDLE;
            crc_reg    <= 16'hFFFF;
            result_reg <= '0;
            byte_index <= '0;
        end else begin
            case (state)
                IDLE: begin
                    if (start) begin
                        crc_reg    <= 16'hFFFF;
                        byte_index <= 4'd0;
                        state      <= CALC;
                    end
                end
                CALC: begin
                    crc_reg <= next_crc;
                    if (byte_index == 4'd12) begin
                        // next_crc inclui o ultimo byte; crc_reg ainda nao.
                        result_reg <= next_crc;
                        state      <= RESULT;
                    end else begin
                        byte_index <= byte_index + 4'd1;
                    end
                end
                RESULT: begin
                    // Publicacao de um ciclo, sem espera por confirmacao.
                    state <= IDLE;
                end
                default: begin
                    state      <= IDLE;
                    crc_reg    <= 16'hFFFF;
                    byte_index <= '0;
                end
            endcase
        end
    end

    // Diagnostico APENAS de simulacao. Sem FIFO, entradas durante ocupacao
    // nao sao armazenadas. O produtor deve respeitar o intervalo contratado.
    // synthesis translate_off
`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (!reset && in_valid && !valid_seen && !capture_allowed)
            $fatal(1, "PROTOCOL_VIOLATION: HASH recebeu nova transferencia ocupado; intervalo minimo de 16 clocks.");
    end
`endif
    // synthesis translate_on
endmodule

`default_nettype wire
