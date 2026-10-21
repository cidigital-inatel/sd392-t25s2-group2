module flow_finalizer (
    input  logic clk,
    input  logic rst,

    input  logic finalize_en,
    input  logic [383:0] flow_entry, // definido para 384 bits a entrada vinda da flow_table

    output logic [279:0] feature_vector, // a saída em si com os 280 bits
    output logic finalize_done  // sinalizador de conclusão - 1 bit
);

    // Campos do registro de entrada.
    logic [63:0] flow_key;
    logic [19:0] packet_count;
    logic [30:0] byte_count;
    logic [47:0] first_timestamp;
    logic [47:0] last_timestamp;
    logic [47:0] duration;

	// Para extrair os campos do registro recebido, deixando os bits de 383 a 211 reservados.
    always_comb begin
        flow_key        = flow_entry[210:147];
        packet_count    = flow_entry[146:127];
        byte_count      = flow_entry[126:96];
        first_timestamp = flow_entry[95:48];
        last_timestamp  = flow_entry[47:0];

        // Cálculo da duração do fluxo.
        duration = last_timestamp - first_timestamp;
    end

    // Finaliza o fluxo quando "finalize_en" estiver ativo e "finalize_done" fica ativo por um ciclo.
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            feature_vector <= '0;
            finalize_done  <= 1'b0;
        end else begin
            finalize_done <= 1'b0; // iniciando zerado

            if (finalize_en) begin
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
