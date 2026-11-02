
module flow_finalizer_v3 (
    input  logic         clk,
    input  logic         rst,

    // Entrada recebida do Controller
    input  logic         fin_valid,
    input  logic [383:0] flow_entry,

    // Saida com as features calculadas
    output logic [247:0] feature_vector,
    output logic         fin_done
);

    // ------------------------------------------------------------
    // Campos extraidos do registro
    // ------------------------------------------------------------
    logic [103:0] flow_key;
    logic [31:0]  packet_count;
    logic [31:0]  byte_count;

    logic [79:0]  first_timestamp;
    logic [79:0]  last_timestamp;
    logic [79:0]  duration;

    // Controle de recebimento
    logic fin_seen;

    // ------------------------------------------------------------
    // Extracao dos campos de flow_entry
    //
    // flow_entry[383:0] contem W1-W12:
    // [103:0]   : flow_key (104 bits)
    // [159:128] : packet_count (32 bits)
    // [191:160] : byte_count (32 bits)
    // [271:192] : first_timestamp (80 bits)
    // [383:288] : last_timestamp (80 bits)
    // ------------------------------------------------------------
    always_comb begin
        flow_key = flow_entry[103:0];

        packet_count = flow_entry[159:128];
        byte_count   = flow_entry[191:160];

        // Timestamp inicial: W7-W9
        first_timestamp = {
            flow_entry[271:256],
            flow_entry[255:192]
        };

        // Timestamp final: W10-W12
        last_timestamp = {
            flow_entry[367:352],
            flow_entry[351:288]
        };

        // Duracao do fluxo (aritmetica unsigned de 80 bits)
        duration = last_timestamp - first_timestamp;
    end

    // ------------------------------------------------------------
    // Recepcao e confirmacao do registro
    // ------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            feature_vector <= '0;
            fin_done       <= 1'b0;
            fin_seen       <= 1'b0;
        end else begin
            // fin_done e um pulso de um ciclo
            fin_done <= 1'b0;

            // Rearma o recebimento quando fin_valid retornar a zero
            if (!fin_valid) begin
                fin_seen <= 1'b0;
            end
            // Processa somente uma vez enquanto fin_valid estiver ativo
            else if (!fin_seen) begin
                feature_vector <= {
                    flow_key,       // 104 bits
                    packet_count,   // 32 bits
                    byte_count,     // 32 bits
                    duration        // 80 bits
                };

                fin_done <= 1'b1;
                fin_seen <= 1'b1;
            end
        end
    end

endmodule
