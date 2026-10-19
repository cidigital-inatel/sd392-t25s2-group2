`timescale 1ns/1ps

// DUT mockup para validar a recepcao dos quadros lidos diretamente do PCAP.
// TREADY, SOP e EOP nao fazem parte da interface do DUT.
// TLAST indica o final do quadro e TUSER indica quadro valido.
//
// Timestamp auxiliar do TSU no formato IEEE 1588 Time-of-Day:
//   tsu_timestamp[79:32] = Seconds (48 bits)
//   tsu_timestamp[31:0]  = Nanoseconds (32 bits)
module mac_rx_mockup (
    input  logic        rx_clk,
    input  logic        rx_axis_aresetn,
    input  logic [63:0] rx_axis_tdata,
    input  logic  [7:0] rx_axis_tkeep,
    input  logic        rx_axis_tvalid,
    input  logic        rx_axis_tlast,
    input  logic        rx_axis_tuser,
    input  logic [79:0] tsu_timestamp,

    output logic        packet_done,
    output logic        packet_error,
    output logic [31:0] packet_id,
    output logic [31:0] packet_byte_count,
    output logic [31:0] packet_word_count,
    output logic [79:0] packet_timestamp
);

    logic        in_packet;
    logic        error_latched;
    logic [31:0] byte_count;
    logic [31:0] word_count;
    logic [79:0] first_timestamp;

    function automatic [4:0] count_valid_bytes(input logic [7:0] keep);
        integer index;
        begin
            count_valid_bytes = 5'd0;
            for (index = 0; index < 8; index = index + 1)
                count_valid_bytes = count_valid_bytes + keep[index];
        end
    endfunction

    function automatic logic valid_keep(input logic [7:0] keep);
        begin
            case (keep)
                8'h01, 8'h03, 8'h07, 8'h0F,
                8'h1F, 8'h3F, 8'h7F, 8'hFF:
                    valid_keep = 1'b1;
                default:
                    valid_keep = 1'b0;
            endcase
        end
    endfunction

    always_ff @(posedge rx_clk or negedge rx_axis_aresetn) begin
        if (!rx_axis_aresetn) begin
            in_packet           <= 1'b0;
            error_latched       <= 1'b0;
            byte_count          <= 32'd0;
            word_count          <= 32'd0;
            first_timestamp     <= 80'd0;

            packet_done         <= 1'b0;
            packet_error        <= 1'b0;
            packet_id           <= 32'd0;
            packet_byte_count   <= 32'd0;
            packet_word_count   <= 32'd0;
            packet_timestamp    <= 80'd0;
        end else begin
            packet_done  <= 1'b0;
            packet_error <= 1'b0;

            if (rx_axis_tvalid) begin
                if (!valid_keep(rx_axis_tkeep))
                    error_latched <= 1'b1;

                // TUSER informa o resultado do quadro no encerramento.
                // Nos beats anteriores, seu valor nao e usado para validar
                // o quadro; no beat com TLAST, 1 significa quadro valido.
                if (rx_axis_tlast && rx_axis_tuser !== 1'b1)
                    error_latched <= 1'b1;

                if (!in_packet) begin
                    in_packet          <= 1'b1;
                    first_timestamp    <= tsu_timestamp;
                    byte_count         <= count_valid_bytes(rx_axis_tkeep);
                    word_count         <= 32'd1;
                end else begin
                    byte_count <= byte_count + count_valid_bytes(rx_axis_tkeep);
                    word_count <= word_count + 32'd1;
                end

                if (rx_axis_tlast) begin
                    packet_done <= 1'b1;
                    packet_id   <= packet_id + 32'd1;

                    if (in_packet) begin
                        packet_byte_count   <= byte_count + count_valid_bytes(rx_axis_tkeep);
                        packet_word_count   <= word_count + 32'd1;
                        packet_timestamp    <= first_timestamp;
                    end else begin
                        packet_byte_count   <= count_valid_bytes(rx_axis_tkeep);
                        packet_word_count   <= 32'd1;
                        packet_timestamp    <= tsu_timestamp;
                    end

                    packet_error <= error_latched
                        | !valid_keep(rx_axis_tkeep)
                        | (rx_axis_tuser !== 1'b1);

                    in_packet     <= 1'b0;
                    error_latched <= 1'b0;
                    byte_count    <= 32'd0;
                    word_count    <= 32'd0;
                end
            end
        end
    end

endmodule
