
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

    // Campos extraidos do registro
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
    // ------------------------------------------------------------
    always_comb begin

        // W1-W4: chave do fluxo (104 bits validos)
        flow_key = flow_entry[103:0];

        // W5: quantidade de pacotes
        packet_count = flow_entry[159:128];

        // W6: quantidade de bytes
        byte_count = flow_entry[191:160];

        // W7-W9: timestamp inicial (80 bits)
        first_timestamp = {
            flow_entry[271:256],
            flow_entry[255:192]
        };

        // W10-W12: timestamp final (80 bits)
        last_timestamp = {
            flow_entry[367:352],
            flow_entry[351:288]
        };

        // Duracao do fluxo
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

            // Confirmacao em pulso de um ciclo
            fin_done <= 1'b0;

            // Libera a recepcao para o proximo registro
            if (!fin_valid) begin
                fin_seen <= 1'b0;
            end

            // Processa somente uma vez enquanto fin_valid estiver ativo
            else if (!fin_seen) begin

                feature_vector <= {
                    flow_key,
                    packet_count,
                    byte_count,
                    duration
                };

                fin_done <= 1'b1;
                fin_seen <= 1'b1;

            end
        end
    end

endmodule
