`timescale 1ns/1ps
`default_nettype none

// ============================================================================
// Packet Parser
// Projeto CI Digital
//
// Função:
//   Extrair metadados de quadros Ethernet II contendo IPv4 + TCP/UDP.
//
// Interface de entrada:
//   - TDATA  : 64 bits
//   - TKEEP  : 1 bit por byte de TDATA
//   - TVALID : indica beat válido
//   - TLAST  : indica último beat do quadro
//   - TUSER  : validade do quadro no último beat
//   - timestamp_in : timestamp associado ao pacote
//
// Convenção de bytes:
//   byte 0 do stream -> TDATA[7:0]
//   byte 1           -> TDATA[15:8]
//   ...
//   byte 7           -> TDATA[63:56]
//
// L3_OFFSET:
//   14 -> Ethernet II (modo principal do projeto)
//    4 -> DLT_NULL/loopback, mantido apenas para compatibilidade de testes
//
// Observação:
//   O Parser não interpreta o formato interno de timestamp_in. O valor é
//   capturado no início do pacote e repassado integralmente na saída.
// ============================================================================

module packet_parser #(
    parameter int TS_WIDTH  = 80,
    parameter int L3_OFFSET = 14
) (
    input  wire                  clk,
    input  wire                  reset,

    input  wire [63:0]           TDATA,
    input  wire [7:0]            TKEEP,
    input  wire                  TVALID,
    input  wire                  TLAST,
    input  wire                  TUSER,
    input  wire [TS_WIDTH-1:0]   timestamp_in,

    output logic [31:0]          src_ip,
    output logic [31:0]          dst_ip,
    output logic [15:0]          src_port,
    output logic [15:0]          dst_port,
    output logic [7:0]           protocol,
    output logic [15:0]          packet_length,
    output logic [TS_WIDTH-1:0]  timestamp,
    output logic                 valid
);

    typedef enum logic [3:0] {
        IDLE,
        ETHERNET,
        IPV4,
        WAIT_L4,
        SELECT_TRANSP,
        TCP_STATE,
        UDP_STATE,
        WAIT_LAST,
        DROP_PROTO
    } state_t;

    state_t state;

    logic [15:0] ethertype;
    logic [3:0]  ip_version;
    logic [3:0]  ihl;
    logic [15:0] transport_offset;
    logic [15:0] byte_offset;
    logic        drop_packet;

    integer i;
    integer valid_bytes;
    integer abs_off;
    logic [7:0] byte_value;

    // Conta os bytes válidos do beat.
    // Contrato do projeto: beats intermediários usam TKEEP=8'hFF;
    // TKEEP parcial é esperado apenas no último beat.
    function automatic integer count_keep(input logic [7:0] keep);
        integer k;
        begin
            count_keep = 0;
            for (k = 0; k < 8; k = k + 1)
                count_keep = count_keep + keep[k];
        end
    endfunction

    // Reset síncrono, ativo em nível alto.
    always_ff @(posedge clk) begin
        if (reset) begin
            state            <= IDLE;
            src_ip           <= '0;
            dst_ip           <= '0;
            src_port         <= '0;
            dst_port         <= '0;
            protocol         <= '0;
            packet_length    <= '0;
            timestamp        <= '0;
            valid            <= 1'b0;

            ethertype        <= '0;
            ip_version       <= '0;
            ihl              <= '0;
            transport_offset <= '0;
            byte_offset      <= '0;
            drop_packet      <= 1'b0;

        end else begin
            // valid é um pulso de um ciclo.
            valid <= 1'b0;

            if (TVALID) begin

                // Início de um novo pacote.
                if (state == IDLE) begin
                    src_ip           <= '0;
                    dst_ip           <= '0;
                    src_port         <= '0;
                    dst_port         <= '0;
                    protocol         <= '0;
                    packet_length    <= '0;
                    timestamp        <= timestamp_in;

                    ethertype        <= '0;
                    ip_version       <= '0;
                    ihl              <= '0;
                    transport_offset <= '0;
                    byte_offset      <= '0;
                    drop_packet      <= 1'b0;

                    if (L3_OFFSET == 14)
                        state <= ETHERNET;
                    else
                        state <= IPV4;
                end

                valid_bytes = count_keep(TKEEP);

                // Parsing byte a byte do beat atual.
                for (i = 0; i < 8; i = i + 1) begin
                    if (TKEEP[i]) begin
                        byte_value = TDATA[(8*i) +: 8];
                        abs_off    = byte_offset + i;

                        // ----------------------------------------------------
                        // Ethernet II
                        // ----------------------------------------------------
                        if (L3_OFFSET == 14) begin
                            case (abs_off)
                                12: begin
                                    ethertype[15:8] <= byte_value;
                                    if (byte_value != 8'h08)
                                        drop_packet <= 1'b1;
                                end

                                13: begin
                                    ethertype[7:0] <= byte_value;
                                    if (byte_value != 8'h00)
                                        drop_packet <= 1'b1;
                                end

                                default: begin
                                end
                            endcase
                        end

                        // ----------------------------------------------------
                        // IPv4
                        // ----------------------------------------------------
                        if (abs_off == L3_OFFSET) begin
                            ip_version <= byte_value[7:4];
                            ihl        <= byte_value[3:0];

                            transport_offset <=
                                L3_OFFSET + ({12'd0, byte_value[3:0]} << 2);

                            if ((byte_value[7:4] != 4'd4) ||
                                (byte_value[3:0] < 4'd5))
                                drop_packet <= 1'b1;
                        end

                        // IPv4 Total Length
                        if (abs_off == (L3_OFFSET + 2))
                            packet_length[15:8] <= byte_value;

                        if (abs_off == (L3_OFFSET + 3))
                            packet_length[7:0] <= byte_value;

                        // Flags + Fragment Offset:
                        // descarta MF=1 ou fragment offset != 0.
                        if (abs_off == (L3_OFFSET + 6)) begin
                            if (byte_value[5] ||
                                (byte_value[4:0] != 5'b0))
                                drop_packet <= 1'b1;
                        end

                        if (abs_off == (L3_OFFSET + 7)) begin
                            if (byte_value != 8'h00)
                                drop_packet <= 1'b1;
                        end

                        // IPv4 Protocol
                        if (abs_off == (L3_OFFSET + 9)) begin
                            protocol <= byte_value;

                            if ((byte_value != 8'd6) &&
                                (byte_value != 8'd17))
                                drop_packet <= 1'b1;
                        end

                        // Source IPv4
                        if (abs_off == (L3_OFFSET + 12))
                            src_ip[31:24] <= byte_value;
                        if (abs_off == (L3_OFFSET + 13))
                            src_ip[23:16] <= byte_value;
                        if (abs_off == (L3_OFFSET + 14))
                            src_ip[15:8] <= byte_value;
                        if (abs_off == (L3_OFFSET + 15))
                            src_ip[7:0] <= byte_value;

                        // Destination IPv4
                        if (abs_off == (L3_OFFSET + 16))
                            dst_ip[31:24] <= byte_value;
                        if (abs_off == (L3_OFFSET + 17))
                            dst_ip[23:16] <= byte_value;
                        if (abs_off == (L3_OFFSET + 18))
                            dst_ip[15:8] <= byte_value;
                        if (abs_off == (L3_OFFSET + 19))
                            dst_ip[7:0] <= byte_value;

                        // ----------------------------------------------------
                        // TCP / UDP
                        // Portas são localizadas dinamicamente pelo IHL.
                        // ----------------------------------------------------
                        if (transport_offset >= (L3_OFFSET + 20)) begin
                            if (abs_off == transport_offset)
                                src_port[15:8] <= byte_value;

                            if (abs_off == (transport_offset + 1))
                                src_port[7:0] <= byte_value;

                            if (abs_off == (transport_offset + 2))
                                dst_port[15:8] <= byte_value;

                            if (abs_off == (transport_offset + 3))
                                dst_port[7:0] <= byte_value;
                        end
                    end
                end

                // FSM de acompanhamento do parsing.
                case (state)
                    IDLE: begin
                        if (L3_OFFSET == 14)
                            state <= ETHERNET;
                        else
                            state <= IPV4;
                    end

                    ETHERNET: state <= IPV4;
                    IPV4:     state <= WAIT_L4;

                    WAIT_L4: begin
                        if (byte_offset >= transport_offset)
                            state <= SELECT_TRANSP;
                    end

                    SELECT_TRANSP: begin
                        if (protocol == 8'd6)
                            state <= TCP_STATE;
                        else if (protocol == 8'd17)
                            state <= UDP_STATE;
                        else
                            state <= DROP_PROTO;
                    end

                    TCP_STATE:  state <= WAIT_LAST;
                    UDP_STATE:  state <= WAIT_LAST;
                    WAIT_LAST:  state <= WAIT_LAST;
                    DROP_PROTO: state <= DROP_PROTO;

                    default: state <= IDLE;
                endcase

                if (drop_packet)
                    state <= DROP_PROTO;

                byte_offset <= byte_offset + valid_bytes;

                // ------------------------------------------------------------
                // Finalização direta no TLAST
                // ------------------------------------------------------------
                // Não há estados pós-TLAST: o Parser libera o próximo pacote
                // no ciclo seguinte.
                //
                // A condição de completude exige que pelo menos os quatro
                // bytes das portas TCP/UDP tenham sido recebidos.
                // ------------------------------------------------------------
                if (TLAST) begin
                    if (TUSER &&
                        !drop_packet &&
                        (state != DROP_PROTO) &&
                        ((L3_OFFSET != 14) || (ethertype == 16'h0800)) &&
                        (ip_version == 4'd4) &&
                        (ihl >= 4'd5) &&
                        ((protocol == 8'd6) || (protocol == 8'd17)) &&
                        ((byte_offset + valid_bytes) >=
                         (transport_offset + 4))) begin

                        valid <= 1'b1;
                    end else begin
                        valid <= 1'b0;
                    end

                    state       <= IDLE;
                    byte_offset <= '0;
                end
            end
        end
    end

endmodule

`default_nettype wire
