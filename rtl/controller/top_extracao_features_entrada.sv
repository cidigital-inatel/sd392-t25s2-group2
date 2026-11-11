`timescale 1ns/1ps
`default_nettype none

module top_extracao_features_com_entrada #(
    parameter bit INVALIDATE_AFTER_SEND = 1'b1,
    parameter int SCAN_ENTRIES = 65536
) (
    input  logic        clk,
    input  logic        rst,

    // Entrada do pacote
    input  logic [31:0] src_ip_in,
    input  logic [31:0] dst_ip_in,
    input  logic [15:0] src_port_in,
    input  logic [15:0] dst_port_in,
    input  logic [7:0]  protocol_in,
    input  logic [15:0] packet_length_in,
    input  logic [79:0] timestamp_in,
    input  logic        in_valid,

    // Indica que a captura dos pacotes terminou
    input  logic        pcap_done,

    // Saída das features
    output logic [247:0] feature_vector,
    output logic         fin_done
);

    // =========================================================
    // Reset síncrono e ativo em nível alto para todos os módulos.
    // =========================================================

    

    // =========================================================
    // Sinais entre FIU, Hash e Controller
    // =========================================================

    logic [15:0]  hash_index;
    logic [103:0] flow_key;
    logic [15:0]  packet_length;
    logic [79:0]  timestamp;
    logic         hash_valid;

    // =========================================================
    // Sinais da memória Flow Table
    // =========================================================

    logic         rd_en;
    logic [19:0]  rd_addr;
    logic [31:0]  rd_data;
    logic         rd_valid;

    logic         wr_en;
    logic [19:0]  wr_addr;
    logic [31:0]  wr_data;
    logic         wr_done;

    // =========================================================
    // Sinais entre Controller e Finalizer
    // =========================================================

    logic [383:0] flow_entry;
    logic         fin_valid;

    // =========================================================
    // 1. Identificação do fluxo + cálculo do hash
    // =========================================================

    fiu_hash_top u_fiu_hash_top (
    .clk              (clk),
    .reset             (rst),

    .src_ip_in        (src_ip_in),
    .dst_ip_in        (dst_ip_in),
    .src_port_in      (src_port_in),
    .dst_port_in      (dst_port_in),
    .protocol_in      (protocol_in),
    .packet_length_in (packet_length_in),
    .timestamp_in     (timestamp_in),
    .in_valid         (in_valid),

    .hash_index       (hash_index),
    .flow_key         (flow_key),
    .packet_length    (packet_length),
    .timestamp        (timestamp),
    .hash_valid       (hash_valid)
);

    // =========================================================
    // 2. Controller
    // =========================================================

    controller #(
        .INVALIDATE_AFTER_SEND (INVALIDATE_AFTER_SEND),
        .SCAN_ENTRIES           (SCAN_ENTRIES)
    ) u_controller (
        .clk          (clk),
        .rst          (rst),

        .hash_index   (hash_index),
        .flow_key     (flow_key),
        .packet_length(packet_length),
        .timestamp    (timestamp),
        .hash_valid   (hash_valid),

        .rd_en        (rd_en),
        .rd_addr      (rd_addr),
        .rd_data      (rd_data),
        .rd_valid     (rd_valid),

        .wr_en        (wr_en),
        .wr_addr      (wr_addr),
        .wr_data      (wr_data),
        .wr_done      (wr_done),

        .flow_entry   (flow_entry),
        .fin_valid    (fin_valid),
        .fin_done     (fin_done),
        .pcap_done    (pcap_done)
    );

    // =========================================================
    // 3. Memória da Flow Table
    // =========================================================

    flow_table #(
        .ADDR_WIDTH (20),
        .DATA_WIDTH (32),
        .DEPTH      (1 << 20)
    ) u_flow_table (
        .clk      (clk),
        .rst      (rst),

        .rd_en    (rd_en),
        .rd_addr  (rd_addr),
        .rd_data  (rd_data),
        .rd_valid (rd_valid),

        .wr_en    (wr_en),
        .wr_addr  (wr_addr),
        .wr_data  (wr_data),
        .wr_done  (wr_done)
    );

    // =========================================================
    // 4. Finalização e geração do vetor de features
    // =========================================================

   flow_finalizer_v5 u_finalizer (
    .clk            (clk),
    .rst            (rst),
    .fin_valid      (fin_valid),
    .flow_entry     (flow_entry),
    .feature_vector (feature_vector),
    .fin_done       (fin_done)
);

endmodule

`default_nettype wire