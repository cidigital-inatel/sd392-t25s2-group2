`timescale 1ns/1ps
`default_nettype none

// Integracao REAL dos dois RTLs: os quatro sinais de saida da FIU
// alimentam diretamente as quatro entradas de dados/validade do Hash.
module fiu_hash_top (
    input wire logic clk,
    input wire logic reset_n,
    input wire logic [31:0] src_ip_in,
    input wire logic [31:0] dst_ip_in,
    input wire logic [15:0] src_port_in,
    input wire logic [15:0] dst_port_in,
    input wire logic [7:0] protocol_in,
    input wire logic [15:0] packet_length_in,
    input wire logic [79:0] timestamp_in,
    input wire logic in_valid,
    output logic [15:0] hash_index,
    output logic [103:0] flow_key,
    output logic [15:0] packet_length,
    output logic [79:0] timestamp,
    output logic hash_valid
);
    wire [103:0] fiu_flow_key;
    wire [15:0] fiu_packet_length;
    wire [79:0] fiu_timestamp;
    wire fiu_valid;

    flow_identification_unit u_fiu (
        .clk, .reset_n,
        .src_ip_in, .dst_ip_in, .src_port_in, .dst_port_in, .protocol_in,
        .packet_length_in, .timestamp_in, .in_valid,
        .flow_key_out(fiu_flow_key), .packet_length_out(fiu_packet_length),
        .timestamp_out(fiu_timestamp), .out_valid(fiu_valid)
    );
    hash_unit u_hash (
        .clk, .reset_n, .flow_key_in(fiu_flow_key),
        .packet_length_in(fiu_packet_length), .timestamp_in(fiu_timestamp),
        .in_valid(fiu_valid), .hash_index_out(hash_index),
        .flow_key_out(flow_key), .packet_length_out(packet_length),
        .timestamp_out(timestamp), .out_valid(hash_valid)
    );
endmodule

`default_nettype wire
