`timescale 1ns/1ps
`default_nettype none

module packet_parser #(
    // Na fase atual de simulacao, timestamp_in e expresso em microssegundos.
    // 64 bits comportam com folga timestamps de PCAP em microssegundos.
    parameter int TS_WIDTH = 64
) (
    input  wire                  clk,
    input  wire                  reset_n,

    // Interface MAC RX
    input  wire [63:0]           TDATA,
    input  wire [7:0]            TKEEP,
    input  wire                  TVALID,
    input  wire                  TLAST,
    input  wire                  TUSER,

    // Simulacao: timestamp proveniente do PCAP, em microssegundos.
    // FPGA: futuramente esta entrada podera ser alimentada pelo TSU.
    input  wire [TS_WIDTH-1:0]   timestamp_in,

    // Metadados extraidos
    output logic [31:0]          src_ip,
    output logic [31:0]          dst_ip,
    output logic [15:0]          src_port,
    output logic [15:0]          dst_port,
    output logic [7:0]           protocol,
    output logic [15:0]          packet_length,
    output logic [TS_WIDTH-1:0]  timestamp,
    output logic                 metadata_valid
);

    // Convencao do projeto:
    // primeiro byte da rede em TDATA[63:56].
    // TKEEP[7] -> TDATA[63:56], ..., TKEEP[0] -> TDATA[7:0].

    typedef enum logic [3:0] {
        IDLE,
        ETHERNET,
        IPV4,
        WAIT_L4,
        SELECT_TRANSP,
        TCP_STATE,
        UDP_STATE,
        WAIT_LAST,
        CHECK_FRAME,
        OUTPUT_STATE,
        DISCARD,
        DROP_PROTO
    } state_t;

    state_t state;

    logic [15:0] ethertype;
    logic [3:0]  ip_version;
    logic [3:0]  ihl;
    logic [15:0] transport_offset;
    logic [7:0]  frag_hi;
    logic [15:0] byte_offset;
    logic        drop_packet;
    logic        frame_valid_latched;

    integer i;
    integer valid_bytes;
    integer abs_off;
    logic [7:0] byte_value;

    function automatic integer count_keep(input logic [7:0] keep);
        integer k;
        begin
            count_keep = 0;
            for (k = 0; k < 8; k = k + 1)
                count_keep = count_keep + keep[k];
        end
    endfunction

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state               <= IDLE;
            src_ip              <= '0;
            dst_ip              <= '0;
            src_port            <= '0;
            dst_port            <= '0;
            protocol            <= '0;
            packet_length       <= '0;
            timestamp           <= '0;
            metadata_valid      <= 1'b0;
            ethertype           <= '0;
            ip_version          <= '0;
            ihl                 <= '0;
            transport_offset    <= '0;
            frag_hi             <= '0;
            byte_offset         <= '0;
            drop_packet         <= 1'b0;
            frame_valid_latched <= 1'b0;
        end else begin
            // Pulso de um ciclo apenas quando os metadados sao liberados.
            metadata_valid <= 1'b0;

            case (state)
                OUTPUT_STATE: begin
                    metadata_valid <= 1'b1;
                    state          <= IDLE;
                    byte_offset    <= '0;
                end

                DISCARD: begin
                    state       <= IDLE;
                    byte_offset <= '0;
                end

                CHECK_FRAME: begin
                    if (frame_valid_latched)
                        state <= OUTPUT_STATE;
                    else
                        state <= DISCARD;
                end

                default: begin
                end
            endcase

            if (TVALID &&
                state != OUTPUT_STATE &&
                state != DISCARD &&
                state != CHECK_FRAME) begin

                // Nao ha SOP. O primeiro TVALID enquanto IDLE inicia o quadro.
                if (state == IDLE) begin
                    state               <= ETHERNET;
                    src_ip              <= '0;
                    dst_ip              <= '0;
                    src_port            <= '0;
                    dst_port            <= '0;
                    protocol            <= '0;
                    packet_length       <= '0;

                    // O Parser apenas registra o timestamp recebido.
                    // Nesta PoC, a unidade e microssegundos.
                    timestamp           <= timestamp_in;

                    ethertype           <= '0;
                    ip_version          <= '0;
                    ihl                 <= '0;
                    transport_offset    <= '0;
                    frag_hi             <= '0;
                    byte_offset         <= '0;
                    drop_packet         <= 1'b0;
                    frame_valid_latched <= 1'b0;
                end

                valid_bytes = count_keep(TKEEP);

                // Extracao por offsets absolutos desde o inicio do Ethernet II.
                for (i = 0; i < 8; i = i + 1) begin
                    if (TKEEP[7-i]) begin
                        byte_value = TDATA[63-(8*i) -: 8];
                        abs_off    = byte_offset + i;

                        case (abs_off)
                            // Ethernet II: EtherType
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

                            // IPv4: Version + IHL
                            14: begin
                                ip_version       <= byte_value[7:4];
                                ihl              <= byte_value[3:0];
                                transport_offset <= 16'd14 +
                                                    ({12'd0, byte_value[3:0]} << 2);

                                if ((byte_value[7:4] != 4'd4) ||
                                    (byte_value[3:0] < 4'd5))
                                    drop_packet <= 1'b1;
                            end

                            // IPv4 Total Length -> packet_length
                            16: packet_length[15:8] <= byte_value;
                            17: packet_length[7:0]  <= byte_value;

                            // Flags + Fragment Offset
                            20: begin
                                frag_hi <= byte_value;

                                // Byte alto de Flags + Fragment Offset:
                                // bit 5 = MF; bits 4:0 = parte alta do Fragment Offset.
                                if (byte_value[5] ||
                                    (byte_value[4:0] != 5'b0))
                                    drop_packet <= 1'b1;
                            end

                            21: begin
                                // Byte baixo do Fragment Offset.
                                if (byte_value != 8'h00)
                                    drop_packet <= 1'b1;
                            end

                            // IPv4 Protocol
                            23: begin
                                protocol <= byte_value;
                                if ((byte_value != 8'd6) &&
                                    (byte_value != 8'd17))
                                    drop_packet <= 1'b1;
                            end

                            // IPv4 Source
                            26: src_ip[31:24] <= byte_value;
                            27: src_ip[23:16] <= byte_value;
                            28: src_ip[15:8]  <= byte_value;
                            29: src_ip[7:0]   <= byte_value;

                            // IPv4 Destination
                            30: dst_ip[31:24] <= byte_value;
                            31: dst_ip[23:16] <= byte_value;
                            32: dst_ip[15:8]  <= byte_value;
                            33: dst_ip[7:0]   <= byte_value;

                            default: begin
                            end
                        endcase

                        // Portas TCP/UDP localizadas pelo IHL.
                        if (transport_offset >= 16'd34) begin
                            if (abs_off == transport_offset)
                                src_port[15:8] <= byte_value;

                            if (abs_off == (transport_offset + 16'd1))
                                src_port[7:0] <= byte_value;

                            if (abs_off == (transport_offset + 16'd2))
                                dst_port[15:8] <= byte_value;

                            if (abs_off == (transport_offset + 16'd3))
                                dst_port[7:0] <= byte_value;
                        end
                    end
                end

                case (state)
                    IDLE:       state <= ETHERNET;
                    ETHERNET:   state <= IPV4;
                    IPV4:       state <= WAIT_L4;

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
                    default: ;
                endcase

                if (drop_packet)
                    state <= DROP_PROTO;

                byte_offset <= byte_offset + valid_bytes;

                // Fim do quadro
                if (TLAST) begin
                    if (drop_packet || state == DROP_PROTO) begin
                        state       <= IDLE;
                        byte_offset <= '0;
                    end else begin
                        // TUSER e amostrado no mesmo ciclo de TLAST.
                        frame_valid_latched <= TUSER;
                        state               <= CHECK_FRAME;
                    end
                end
            end
        end
    end

endmodule

`default_nettype wire
