// VERSÃO 5 - alterado:
// Timestamp com novo formato (segundos e nanossegundos)

module flow_finalizer_v5 (
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

    logic [79:0] first_timestamp; 
    logic [79:0] last_timestamp;
    logic [79:0] duration;

    logic [47:0] first_seconds;
    logic [47:0] last_seconds;
    logic [31:0] first_nanoseconds;
    logic [31:0] last_nanoseconds;
    logic [47:0] duration_seconds;
    logic [31:0] duration_nanoseconds;

    // Controle de recebimento
    logic fin_seen;

    // ---------------------------------------------------------------------------------------------------------
    // Extração dos campos do registro recebido e depois junção na ordem redefinida já com timestamp redesenhado
    // ---------------------------------------------------------------------------------------------------------

    always_comb begin
        // Chave do fluxo: 104 bits
        flow_key = flow_entry[103:0];
        // Quantidade de pacotes: 32 bits
        packet_count = flow_entry[159:128];
        // Quantidade de bytes: 32 bits
        byte_count = flow_entry[191:160];
        // Timestamp inicial: 80 bits
        first_timestamp = flow_entry[271:192];
        // Timestamp final: 80 bits
        last_timestamp = flow_entry[367:288];
        // Timestamp: [79:32] segundos e [31:0] nanossegundos
        first_seconds     = first_timestamp[79:32];
        first_nanoseconds = first_timestamp[31:0];
        last_seconds      = last_timestamp[79:32];
        last_nanoseconds  = last_timestamp[31:0];

        // Calculo da duração com segundos e nanossegundos
        if (last_nanoseconds >= first_nanoseconds) begin
            duration_seconds      = last_seconds - first_seconds;
            duration_nanoseconds = last_nanoseconds - first_nanoseconds;
        end else begin
            duration_seconds      = last_seconds - first_seconds - 1'b1;
            duration_nanoseconds = 32'd1000000000 + last_nanoseconds - first_nanoseconds;
        end

        duration = {duration_seconds, duration_nanoseconds};
    end

    // ------------------------------------------------
    // Recepcao e confirmacao do registro
    // ------------------------------------------------
    always_ff @(posedge clk) begin

        if (rst) begin
            feature_vector <= '0;
            fin_done       <= 1'b0;
            fin_seen       <= 1'b0;
        end else begin
            // fin_done e um pulso de um ciclo
            fin_done <= 1'b0;

            // Rearma quando fin_valid retornar a zero
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