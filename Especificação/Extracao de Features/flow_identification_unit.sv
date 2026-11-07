`timescale 1ns/1ps
`default_nettype none

// FIU da Semana 6, baseada na interface de dados do pacote publico de Bruno.
// Recepcao unica por periodo alto de valid -> captura -> start -> publicacao.
// Um registro local, sem FIFO ou ready. Reset assincrono ativo alto.
// timestamp_in[79:32] = segundos; [31:0] = nanossegundos (passagem integral).
module flow_identification_unit (
    input wire logic         clk,
    input wire logic         reset,
    input wire logic [31:0]  src_ip_in,
    input wire logic [31:0]  dst_ip_in,
    input wire logic [15:0]  src_port_in,
    input wire logic [15:0]  dst_port_in,
    input wire logic [7:0]   protocol_in,
    input wire logic [15:0]  packet_length_in,
    input wire logic [79:0]  timestamp_in,
    input wire logic         in_valid,
    output logic [103:0] flow_key_out,
    output logic [15:0]  packet_length_out,
    output logic [79:0]  timestamp_out,
    output logic         out_valid
);
    typedef enum logic {IDLE, PUBLISH} state_t;
    state_t state;
    logic [31:0] src_ip_reg, dst_ip_reg;
    logic [15:0] src_port_reg, dst_port_reg, length_reg;
    logic [7:0] protocol_reg;
    logic [79:0] timestamp_reg;
    logic start;
    logic valid_seen;
    logic capture_allowed;

    assign capture_allowed = (state == IDLE) && !start;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            src_ip_reg    <= '0;
            dst_ip_reg    <= '0;
            src_port_reg  <= '0;
            dst_port_reg  <= '0;
            protocol_reg  <= '0;
            length_reg    <= '0;
            timestamp_reg <= '0;
            start         <= 1'b0;
            valid_seen    <= 1'b0;
        end else begin
            start <= 1'b0;
            if (!in_valid)
                valid_seen <= 1'b0;
            else
                valid_seen <= 1'b1;
            if (in_valid && !valid_seen && capture_allowed) begin
                src_ip_reg    <= src_ip_in;
                dst_ip_reg    <= dst_ip_in;
                src_port_reg  <= src_port_in;
                dst_port_reg  <= dst_port_in;
                protocol_reg  <= protocol_in;
                length_reg    <= packet_length_in;
                timestamp_reg <= timestamp_in;
                start         <= 1'b1;
            end
        end
    end

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state             <= IDLE;
            flow_key_out      <= '0;
            packet_length_out <= '0;
            timestamp_out     <= '0;
            out_valid         <= 1'b0;
        end else begin
            out_valid <= 1'b0;
            case (state)
                IDLE: begin
                    if (start) begin
                        flow_key_out <= {src_ip_reg, dst_ip_reg,
                                         src_port_reg, dst_port_reg, protocol_reg};
                        packet_length_out <= length_reg;
                        timestamp_out <= timestamp_reg;
                        out_valid <= 1'b1;
                        state <= PUBLISH;
                    end
                end
                PUBLISH: state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end

    // synthesis translate_off
`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (!reset && in_valid && !valid_seen && !capture_allowed)
            $fatal(1, "PROTOCOL_VIOLATION: FIU recebeu nova transferencia ocupado; intervalo local minimo de 3 clocks.");
    end
`endif
    // synthesis translate_on
endmodule

`default_nettype wire
