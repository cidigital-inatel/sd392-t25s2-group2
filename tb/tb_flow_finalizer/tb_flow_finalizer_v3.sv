
`timescale 1ns/1ps

module tb_flow_finalizer_v3;

    logic clk;
    logic rst;
    logic fin_valid;
    logic [383:0] flow_entry;
    logic [247:0] feature_vector;
    logic fin_done;

    integer testes_ok;
    integer testes_erro_detectados;
    integer testes_falhos;

    // Instância do modulo
    flow_finalizer_v3 dut (
        .clk            (clk),
        .rst            (rst),
        .fin_valid      (fin_valid),
        .flow_entry     (flow_entry),
        .feature_vector (feature_vector),
        .fin_done  		(fin_done)
    );

    // Geracao do clock de 10 ns
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Aplica os valores e confere o resultado
    task automatic executar_teste(
        input integer numero,
        input logic [383:0] entrada,
        input logic [127:0] chave_esperada,
        input logic [31:0] pacotes_esperados,
        input logic [31:0] bytes_esperados,
        input logic [47:0] duracao_esperada,
        input bit teste_deve_passar
    );
        logic resultado_correto;

        begin
            @(negedge clk);
            flow_entry = entrada;
            fin_valid = 1'b1;

            @(posedge clk);
            #1;

            // Conferência dos campos do vetor de saida de acordo com a tabela
            resultado_correto =
                (feature_vector[239:112] == chave_esperada) &&
                (feature_vector[111:80]  == pacotes_esperados) &&
                (feature_vector[79:48]   == bytes_esperados) &&
                (feature_vector[47:0]    == duracao_esperada) &&
                (fin_done == 1'b1);

            $display("");
            $display("--------------------------------");
            $display("TESTE %0d", numero);
            $display("--------------------------------");
            $display("Chave   : %h", feature_vector[239:112]);
            $display("Pacotes : %0d", feature_vector[111:80]);
            $display("Bytes   : %0d", feature_vector[79:48]);
            $display("Duracao : %0d", feature_vector[47:0]);

            if (teste_deve_passar) begin
                if (resultado_correto) begin
                    $display("TESTE OK: valores corretos.");
                    testes_ok = testes_ok + 1;
                end else begin
                    $display("FALHA: valores diferentes do esperado.");
                    testes_falhos = testes_falhos + 1;
                end
            end else begin
                if (!resultado_correto) begin
                    $display("TESTE OK: diferenca identificada.");
                    testes_erro_detectados =
                        testes_erro_detectados + 1;
                end else begin
                    $display("FALHA: diferenca nao identificada.");
                    testes_falhos = testes_falhos + 1;
                end
            end

            @(negedge clk);
            fin_valid = 1'b0;

            @(posedge clk);
            #1;

            if (fin_done !== 1'b0) begin
                $display("FALHA: fin_done deveria voltar a zero.");
                testes_falhos = testes_falhos + 1;
            end
        end
    endtask

    initial begin
        rst = 1'b1;
        fin_valid = 1'b0;
        flow_entry = '0;

        testes_ok = 0;
        testes_erro_detectados = 0;
        testes_falhos = 0;

        repeat (2) @(negedge clk);
        rst = 1'b0;

        // Ordem de flow_entry:
        // [383:288] Timestamp final - W10 a W12
        // [287:192] Timestamp inicial - W7 a W9
        // [191:160] Quantidade de bytes - W6
        // [159:128] Quantidade de pacotes - W5
        // [127:0]   Chave do fluxo - W1 a W4
        // Os timestamps de teste usam 48 bits inferiores de cada campo de 96 bits.

        // Teste 1: registro válido
        executar_teste(
            1,
            {48'b0, 48'd150, 48'b0, 48'd100, 32'd1200, 32'd3,
             128'h123456789ABCDEF00112233445566778},
             128'h123456789ABCDEF00112233445566778,
             32'd3, 32'd1200, 48'd50, 1'b1
        );

        // Teste 2: duracao esperada incorreta
        executar_teste(
            2,
            {48'b0, 48'd350, 48'b0, 48'd200, 32'd800, 32'd4,
             128'h11112222333344445555666677778888},
             128'h11112222333344445555666677778888,
             32'd4, 32'd800, 48'd100, 1'b0
        );

        // Teste 3: segundo registro valido
        executar_teste(
            3,
            {48'b0, 48'd1100, 48'b0, 48'd1000, 32'd2000, 32'd5,
             128'hABCDEF1234567890ABCDEF1234567890},
             128'hABCDEF1234567890ABCDEF1234567890,
             32'd5, 32'd2000, 48'd100, 1'b1
        );

        // Teste 4: quantidade de bytes esperada incorreta
        executar_teste(
            4,
            {48'b0, 48'd450, 48'b0, 48'd400, 32'd500, 32'd2,
             128'h55556666777788889999AAAABBBBCCCC},
             128'h55556666777788889999AAAABBBBCCCC,
             32'd2, 32'd1200, 48'd50, 1'b0
        );

        // Teste 5: chave esperada incorreta
        // A entrada e valida, mas a chave esperada e diferente.
        executar_teste(
            5,
            {48'b0, 48'd600, 48'b0, 48'd500, 32'd1000, 32'd6,
             128'h123456789ABCDEF00112233445566778},
             128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF,
             32'd6, 32'd1000, 48'd100, 1'b1
        );

        $display("");
        $display("--------------------------------");
        $display("RESUMO DOS TESTES");
        $display("--------------------------------");
        $display("Testes corretos       : %0d", testes_ok);
        $display("Erros esperados        : %0d", testes_erro_detectados);
        $display("Testes com falha       : %0d", testes_falhos);

        $finish;
    end

endmodule
