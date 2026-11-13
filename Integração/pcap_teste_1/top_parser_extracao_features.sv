`timescale 1ns/1ps
`default_nettype none

// ============================================================================
// Top ponta a ponta
// Packet Parser -> FIU -> Hash -> Controller -> Flow Table -> Flow Finalizer
//
// Reset: sincrono, ativo em nivel alto.
// Timestamp: campo opaco no Parser; contrato do sistema:
//   [79:32] = seconds
//   [31:0]  = nanoseconds
// ============================================================================
module top_parser_extracao_features #(
    parameter int L3_OFFSET = 14,
    parameter bit INVALIDATE_AFTER_SEND = 1'b1,
    parameter int SCAN_ENTRIES = 65536
) (
    input  wire logic        clk,
    input  wire logic        reset,

    input  wire logic [63:0] TDATA,
    input  wire logic [7:0]  TKEEP,
    input  wire logic        TVALID,
    input  wire logic        TLAST,
    input  wire logic        TUSER,
    input  wire logic [79:0] timestamp_in,

    input  wire logic        pcap_done,

    output logic [247:0]     feature_vector,
    output logic             fin_done
);

    logic [31:0] parser_src_ip;
    logic [31:0] parser_dst_ip;
    logic [15:0] parser_src_port;
    logic [15:0] parser_dst_port;
    logic [7:0]  parser_protocol;
    logic [15:0] parser_packet_length;
    logic [79:0] parser_timestamp;
    logic        parser_valid;

    packet_parser #(
        .TS_WIDTH(80),
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

    top_extracao_features_com_entrada #(
        .INVALIDATE_AFTER_SEND(INVALIDATE_AFTER_SEND),
        .SCAN_ENTRIES(SCAN_ENTRIES)
    ) u_features (
        .clk              (clk),
        .rst              (reset),

        .src_ip_in        (parser_src_ip),
        .dst_ip_in        (parser_dst_ip),
        .src_port_in      (parser_src_port),
        .dst_port_in      (parser_dst_port),
        .protocol_in      (parser_protocol),
        .packet_length_in (parser_packet_length),
        .timestamp_in     (parser_timestamp),
        .in_valid         (parser_valid),

        .pcap_done        (pcap_done),

        .feature_vector   (feature_vector),
        .fin_done         (fin_done)
    );

endmodule

`default_nettype wire
