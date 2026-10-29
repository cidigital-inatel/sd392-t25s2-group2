 // VERSÃO 3

module flow_finalizer_v3 (
    input  logic         clk,
    input  logic         rst,

    // Entrada quer seá recebida do Controller
    input  logic         fin_valid,
    input  logic [383:0] flow_entry,

    // Saida com as features calculadas/analisadas
    output logic [247:0] feature_vector,
    output logic         fin_done
);

    logic [127:0] flow_key;
    logic [31:0]  packet_count;
    logic [31:0]  byte_count;
    logic [47:0] first_timestamp;
    logic [47:0] last_timestamp;
    logic [47:0] duration;

    logic flow_ready; // Sinal interno do módulo

    assign flow_ready = !rst;

    // Organizacao de flow_entry conforme a tabela de fluxo da Alessandra:
    // W1 a W4  - Chave do fluxo          [127:0]
    // W5       - Quantidade de pacotes   [159:128]
    // W6       - Quantidade de bytes     [191:160]
    // W7 a W9  - Timestamp inicial       [287:192]
    // W10 a W12- Timestamp final         [383:288]
    //
    // Utilizados os 48 bits inferiores de cada campo de timestamp.

    always_comb begin
        flow_key        = flow_entry[127:0];
        packet_count    = flow_entry[159:128];
        byte_count      = flow_entry[191:160];

        first_timestamp = flow_entry[239:192];
        last_timestamp  = flow_entry[335:288];

        duration = last_timestamp - first_timestamp;
    end

    // Ao receber uma entrada válida, registra as features
    // e sinaliza a conclusão em um ciclo de clock.
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            feature_vector <= '0;
            fin_done  <= 1'b0;
        end else begin
            fin_done <= 1'b0;

            if (fin_valid && flow_ready) begin
                feature_vector <= {
                    8'b0,
                    flow_key,
                    packet_count,
                    byte_count,
                    duration
                };

                fin_done <= 1'b1;
            end
        end
    end

endmodule
