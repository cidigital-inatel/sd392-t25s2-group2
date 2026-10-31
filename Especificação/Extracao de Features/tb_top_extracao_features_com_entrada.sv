`timescale 1ns/1ps
`default_nettype none

module tb_top_extracao_features_com_entrada;

    localparam integer NUM_VETORES = 181;
    localparam integer INTERVALO_PACOTES = 80;
    localparam integer TEMPO_LIMITE_SCAN = 300000;

    logic clk = 1'b0;
    logic reset_n = 1'b0;
    logic in_valid = 1'b0;
    logic pcap_done = 1'b0;

    logic [31:0] src_ip_in = '0;
    logic [31:0] dst_ip_in = '0;
    logic [15:0] src_port_in = '0;
    logic [15:0] dst_port_in = '0;
    logic [7:0]  protocol_in = '0;
    logic [15:0] packet_length_in = '0;
    logic [79:0] timestamp_in = '0;

    logic [247:0] feature_vector;
    logic fin_done;

    // [215:112] = chave de fluxo (104 bits)
    // [111:96]  = tamanho do pacote (16 bits)
    // [95:16]   = timestamp (80 bits)
    // [15:0]    = CRC16 esperado
    logic [215:0] vectors [0:NUM_VETORES-1];

    integer i;
    integer features_count;
    integer timeout_count;

    always #5 clk = ~clk;

    // O Top possui somente as portas externas de entrada e as duas saidas
    // do Finalizer. Os sinais de hash/validacao sao observados internamente.
    top_extracao_features_com_entrada dut (
        .clk              (clk),
        .reset_n          (reset_n),
        .src_ip_in        (src_ip_in),
        .dst_ip_in        (dst_ip_in),
        .src_port_in      (src_port_in),
        .dst_port_in      (dst_port_in),
        .protocol_in      (protocol_in),
        .packet_length_in (packet_length_in),
        .timestamp_in     (timestamp_in),
        .in_valid         (in_valid),
        .pcap_done        (pcap_done),
        .feature_vector   (feature_vector),
        .fin_done         (fin_done)
    );

    // fin_done indica que feature_vector foi atualizado.
    always @(posedge clk) begin
        if (!reset_n)
            features_count <= 0;
        else if (fin_done)
            features_count <= features_count + 1;
    end

    initial begin
        features_count = 0;

        $readmemh("hash_vectors.mem", vectors);

        $display("==================================================");
        $display("TB de integracao: %0d vetores", NUM_VETORES);
        $display("==================================================");

        // Reset
        repeat (5) @(negedge clk);
        reset_n = 1'b1;
        repeat (5) @(negedge clk);

        // Envio serial: um pacote por vez.
        for (i = 0; i < NUM_VETORES; i = i + 1) begin
            @(negedge clk);
            src_ip_in        = vectors[i][215:184];
            dst_ip_in        = vectors[i][183:152];
            src_port_in      = vectors[i][151:136];
            dst_port_in      = vectors[i][135:120];
            protocol_in      = vectors[i][119:112];
            packet_length_in = vectors[i][111:96];
            timestamp_in     = vectors[i][95:16];
            in_valid         = 1'b1;

            @(negedge clk);
            in_valid = 1'b0;

            // Aguarda o resultado do Hash Unit.
            timeout_count = 0;
            while (dut.hash_valid !== 1'b1 && timeout_count < 40) begin
                @(negedge clk);
                timeout_count = timeout_count + 1;
            end

            if (dut.hash_valid !== 1'b1) begin
                $display("ERRO: timeout aguardando hash_valid no vetor %0d", i);
                $fatal(1);
            end

            // Confere o CRC16 calculado pelo hardware.
            if (dut.hash_index !== vectors[i][15:0]) begin
                $display("ERRO CRC no vetor %0d: esperado=%04h obtido=%04h",
                         i, vectors[i][15:0], dut.hash_index);
                $fatal(1);
            end

            // Confere se a metadata que chegou ao Controller corresponde
            // ao vetor aplicado na entrada.
            if (dut.flow_key !== vectors[i][215:112]) begin
                $display("ERRO: chave incorreta no vetor %0d", i);
                $fatal(1);
            end

            if (dut.packet_length !== vectors[i][111:96]) begin
                $display("ERRO: tamanho incorreto no vetor %0d", i);
                $fatal(1);
            end

            if (dut.timestamp !== vectors[i][95:16]) begin
                $display("ERRO: timestamp incorreto no vetor %0d", i);
                $fatal(1);
            end

            // O Controller nao possui ready/FIFO. Este intervalo conservador
            // permite concluir a consulta/atualizacao antes do proximo pacote.
            repeat (INTERVALO_PACOTES) @(negedge clk);

            if ((i % 20) == 0)
                $display("Vetores enviados: %0d/%0d", i+1, NUM_VETORES);
        end

        $display("Todos os pacotes enviados. Solicitando varredura...");

        @(negedge clk);
        pcap_done = 1'b1;
        @(negedge clk);
        pcap_done = 1'b0;

        // Aguarda o pulso interno scan_done do Controller.
        timeout_count = 0;
        while (dut.u_controller.scan_done !== 1'b1 &&
               timeout_count < TEMPO_LIMITE_SCAN) begin
            @(negedge clk);
            timeout_count = timeout_count + 1;
        end

        if (dut.u_controller.scan_done !== 1'b1) begin
            $display("ERRO: timeout aguardando scan_done.");
            $fatal(1);
        end

        repeat (5) @(negedge clk);

        $display("==================================================");
        $display("SIMULACAO CONCLUIDA");
        $display("Pacotes enviados: %0d", NUM_VETORES);
        $display("Features finalizadas: %0d", features_count);
        $display("A quantidade de features pode ser menor que %0d devido a colisoes CRC16.",
                 NUM_VETORES);
        $display("PASSOU: CRCs e metadados conferidos; varredura concluida.");
        $display("==================================================");

        $finish;
    end

endmodule

`default_nettype wire
