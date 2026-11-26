`timescale 1ns/1ps
`default_nettype none

// ============================================================================
// TOP UNIFICADO - Extracao de Features com Packet Parser
//
// Cadeia:
// MAC/PCAP -> Packet Parser -> FIU -> Hash -> Controller
//          -> Flow Table -> Flow Finalizer
//
// Reset: sincrono, ativo em nivel alto.
// Timestamp:
//   [79:32] = segundos (48 bits)
//   [31:0]  = nanossegundos (32 bits)
// ============================================================================
module top_extracao_features_com_parser #(
    parameter int L3_OFFSET = 14,
    parameter bit INVALIDATE_AFTER_SEND = 1'b1,
    parameter int SCAN_ENTRIES = 65536
) (
    input  wire logic        clk,
    input  wire logic        reset,

    // Interface de entrada do Packet Parser
    input  wire logic [63:0] TDATA,
    input  wire logic [7:0]  TKEEP,
    input  wire logic        TVALID,
    input  wire logic        TLAST,
    input  wire logic        TUSER,
    input  wire logic [79:0] timestamp_in,

    // Fim dos dados de entrada
    input  wire logic        pcap_done,

    // Saida final
    output logic [247:0]     feature_vector,
    output logic             fin_done
);

    // ========================================================================
    // Parser -> FIU/Hash
    // ========================================================================
    logic [31:0] parser_src_ip;
    logic [31:0] parser_dst_ip;
    logic [15:0] parser_src_port;
    logic [15:0] parser_dst_port;
    logic [7:0]  parser_protocol;
    logic [15:0] parser_packet_length;
    logic [79:0] parser_timestamp;
    logic        parser_valid;

    // ========================================================================
    // FIU/Hash -> Controller
    // ========================================================================
    logic [15:0]  hash_index;
    logic [103:0] flow_key;
    logic [15:0]  packet_length;
    logic [79:0]  timestamp;
    logic         hash_valid;

    // ========================================================================
    // Controller <-> Flow Table
    // ========================================================================
    logic         rd_en;
    logic [19:0]  rd_addr;
    logic [31:0]  rd_data;
    logic         rd_valid;

    logic         wr_en;
    logic [19:0]  wr_addr;
    logic [31:0]  wr_data;
    logic         wr_done;

    // ========================================================================
    // Controller -> Finalizer
    // ========================================================================
    logic [383:0] flow_entry;
    logic         fin_valid;

    // ========================================================================
    // 1. Packet Parser
    // ========================================================================
    packet_parser #(
        .TS_WIDTH (80),
        .L3_OFFSET(L3_OFFSET)
    ) u_parser (
        .clk           (clk),
        .reset         (reset),
        .TDATA         (TDATA),
        .TKEEP         (TKEEP),
        .TVALID        (TVALID),
        .TLAST         (TLAST),
        .TUSER         (TUSER),
        .timestamp_in  (timestamp_in),

        .src_ip        (parser_src_ip),
        .dst_ip        (parser_dst_ip),
        .src_port      (parser_src_port),
        .dst_port      (parser_dst_port),
        .protocol      (parser_protocol),
        .packet_length (parser_packet_length),
        .timestamp     (parser_timestamp),
        .valid         (parser_valid)
    );

    // ========================================================================
    // 2. FIU + Hash
    // ========================================================================
    fiu_hash_top u_fiu_hash_top (
        .clk              (clk),
        .reset            (reset),

        .src_ip_in        (parser_src_ip),
        .dst_ip_in        (parser_dst_ip),
        .src_port_in      (parser_src_port),
        .dst_port_in      (parser_dst_port),
        .protocol_in      (parser_protocol),
        .packet_length_in (parser_packet_length),
        .timestamp_in     (parser_timestamp),
        .in_valid         (parser_valid),

        .hash_index       (hash_index),
        .flow_key         (flow_key),
        .packet_length    (packet_length),
        .timestamp        (timestamp),
        .hash_valid       (hash_valid)
    );

    // ========================================================================
    // 3. Controller
    // ========================================================================
    controller #(
        .INVALIDATE_AFTER_SEND(INVALIDATE_AFTER_SEND),
        .SCAN_ENTRIES         (SCAN_ENTRIES)
    ) u_controller (
        .clk           (clk),
        .rst           (reset),

        .hash_index    (hash_index),
        .flow_key      (flow_key),
        .packet_length (packet_length),
        .timestamp     (timestamp),
        .hash_valid    (hash_valid),

        .rd_en         (rd_en),
        .rd_addr       (rd_addr),
        .rd_data       (rd_data),
        .rd_valid      (rd_valid),

        .wr_en         (wr_en),
        .wr_addr       (wr_addr),
        .wr_data       (wr_data),
        .wr_done       (wr_done),

        .flow_entry    (flow_entry),
        .fin_valid     (fin_valid),
        .fin_done      (fin_done),
        .pcap_done     (pcap_done)
    );

    // ========================================================================
    // 4. Flow Table
    // ========================================================================
    flow_table #(
        .ADDR_WIDTH(20),
        .DATA_WIDTH(32),
        .DEPTH     (1 << 20)
    ) u_flow_table (
        .clk      (clk),
        .rst      (reset),

        .rd_en    (rd_en),
        .rd_addr  (rd_addr),
        .rd_data  (rd_data),
        .rd_valid (rd_valid),

        .wr_en    (wr_en),
        .wr_addr  (wr_addr),
        .wr_data  (wr_data),
        .wr_done  (wr_done)
    );

    // ========================================================================
    // 5. Flow Finalizer
    // ========================================================================
    flow_finalizer_v5 u_finalizer (
        .clk            (clk),
        .rst            (reset),
        .fin_valid      (fin_valid),
        .flow_entry     (flow_entry),
        .feature_vector (feature_vector),
        .fin_done       (fin_done)
    );

endmodule

`default_nettype wire
