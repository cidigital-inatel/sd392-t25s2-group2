// VERSÃO 4 - alterado:
//Campo	    Largura
//Chave	    104 bits
//Pacotes	32 bits
//Bytes	    32 bits
//Duração	80 bits
//Total	    248 bits

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

    // Controle de recebimento
    logic fin_seen;

    // --------------------------------------------------------
    // Extração dos campos do registro recebido e depois junção
	// na ordem redefinida
    // --------------------------------------------------------

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
        // Duracao: timestamp final - inicial
        duration = last_timestamp - first_timestamp;
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
