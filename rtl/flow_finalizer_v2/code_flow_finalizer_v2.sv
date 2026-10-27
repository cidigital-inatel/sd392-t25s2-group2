// VERSÃO 2 - PARA SEMANA 6

module flow_finalizer_v2 (
    input  logic         clk,
    input  logic         rst,

    // Interface de entrada: registro de fluxo vindo da etapa anterior assim como definido na reunião da semana 5
    input  logic         flow_valid,
    output logic         flow_ready,
    input  logic [383:0] flow_entry,

    // Saida com as features do fluxo finalizado e analisado
    output logic [279:0] feature_vector,
    output logic         finalize_done
);

    logic [63:0] flow_key;
    logic [19:0] packet_count;
    logic [30:0] byte_count;
    logic [47:0] first_timestamp;
    logic [47:0] last_timestamp;
    logic [47:0] duration;

    // Para o módulo somente receber um registro a cada ciclo.
    assign flow_ready = !rst;

    always_comb begin
        flow_key        = flow_entry[210:147];
        packet_count    = flow_entry[146:127];
        byte_count      = flow_entry[126:96];
        first_timestamp = flow_entry[95:48];
        last_timestamp  = flow_entry[47:0];
        duration        = last_timestamp - first_timestamp;
    end

    // Ao receber um registro valido, monta o vetor e sinaliza a conclusao.
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            feature_vector <= '0;
            finalize_done  <= 1'b0;
        end else begin
            finalize_done <= 1'b0;

            if (flow_valid && flow_ready) begin
                feature_vector <= {
                    21'b0,
                    flow_key,
                    packet_count,
                    byte_count,
                    first_timestamp,
                    last_timestamp,
                    duration
                };
                finalize_done <= 1'b1;
            end
        end
    end

endmodule
