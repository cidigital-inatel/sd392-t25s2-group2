
module top_extracao_features #(
    parameter bit INVALIDATE_AFTER_SEND = 1'b1,
    parameter int SCAN_ENTRIES = 65536
)(
    input  logic         clk,
    input  logic         rst,

    // Entrada dos pacotes
    input  logic [15:0]  hash_index,
    input  logic [103:0] flow_key,
    input  logic [15:0]  packet_length,
    input  logic [79:0]  timestamp,
    input  logic         hash_valid,

    // Indica o fim da captura dos pacotes
    input  logic         pcap_done,

    // Saida das features
    output logic [247:0] feature_vector,
    output logic         fin_done
);

    // ------------------------------------------------------------
    // Sinais internos: Controller <-> Flow Table
    // ------------------------------------------------------------
    logic         rd_en;
    logic [19:0]  rd_addr;
    logic [31:0]  rd_data;
    logic         rd_valid;

    logic         wr_en;
    logic [19:0]  wr_addr;
    logic [31:0]  wr_data;
    logic         wr_done;

    // ------------------------------------------------------------
    // Sinais internos: Controller <-> Flow Finalizer
    // ------------------------------------------------------------
    logic [383:0] flow_entry;
    logic         fin_valid;

    // ------------------------------------------------------------
    // Controller
    // ------------------------------------------------------------
    controller #(
        .INVALIDATE_AFTER_SEND(INVALIDATE_AFTER_SEND),
        .SCAN_ENTRIES(SCAN_ENTRIES)
    ) u_controller (
        .clk(clk),
        .rst(rst),

        .hash_index(hash_index),
        .flow_key(flow_key),
        .packet_length(packet_length),
        .timestamp(timestamp),
        .hash_valid(hash_valid),

        .rd_en(rd_en),
        .rd_addr(rd_addr),
        .rd_data(rd_data),
        .rd_valid(rd_valid),

        .wr_en(wr_en),
        .wr_addr(wr_addr),
        .wr_data(wr_data),
        .wr_done(wr_done),

        .flow_entry(flow_entry),
        .fin_valid(fin_valid),
        .fin_done(fin_done),

        .pcap_done(pcap_done)
    );

    // ------------------------------------------------------------
    // Flow Table
    // ------------------------------------------------------------
    flow_table u_flow_table (
        .clk(clk),
        .rst(rst),

        .rd_en(rd_en),
        .rd_addr(rd_addr),
        .rd_data(rd_data),
        .rd_valid(rd_valid),

        .wr_en(wr_en),
        .wr_addr(wr_addr),
        .wr_data(wr_data),
        .wr_done(wr_done)
    );

    // ------------------------------------------------------------
    // Flow Finalizer
    // ------------------------------------------------------------
    flow_finalizer_v3 u_finalizer (
        .clk(clk),
        .rst(rst),

        .fin_valid(fin_valid),
        .flow_entry(flow_entry),

        .feature_vector(feature_vector),
        .fin_done(fin_done)
    );

endmodule
