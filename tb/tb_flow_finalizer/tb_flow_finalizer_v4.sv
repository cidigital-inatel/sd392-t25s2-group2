// VERSÃO 4

`timescale 1ns/1ps

module tb_flow_finalizer_v4;

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
    flow_finalizer_v4 dut (
        .clk            (clk),
        .rst            (rst),
        .fin_valid      (fin_valid),
        .flow_entry     (flow_entry),
        .feature_vector (feature_vector),
        .fin_done       (fin_done)
    );

    // Geracao do clock de 10 ns
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Aplica os valores e confere o resultado
    task automatic executar_teste(
        input integer numero,
        input logic [383:0] entrada,
        input logic [103:0] chave_esperada,
        input logic [31:0] pacotes_esperados,
        input logic [31:0] bytes_esperados,
        input logic [79:0] duracao_esperada,
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
                (feature_vector[247:144] == chave_esperada) &&
                (feature_vector[143:112] == pacotes_esperados) &&
                (feature_vector[111:80]  == bytes_esperados) &&
                (feature_vector[79:0]    == duracao_esperada) &&
                (fin_done == 1'b1);

            $display("");
            $display("--------------------------------");
            $display("TESTE %0d", numero);
            $display("--------------------------------");
            $display("Chave   : %h", feature_vector[247:144]);
            $display("Pacotes : %0d", feature_vector[143:112]);
            $display("Bytes   : %0d", feature_vector[111:80]);
            $display("Duracao : %0d", feature_vector[79:0]);

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
        // [383:368] Reservado (16 bits)
        // [367:288] Timestamp final (80 bits)
        // [287:272] Reservado (16 bits)
        // [271:192] Timestamp inicial (80 bits)
        // [191:160] Quantidade de bytes (32 bits)
        // [159:128] Quantidade de pacotes (32 bits)
        // [127:104] Reservado (24 bits)
        // [103:0]   Chave do fluxo (104 bits)

        // Teste 1: registro válido
        executar_teste(
            1,
            {16'b0, 80'd150, 16'b0, 80'd100, 32'd1200, 32'd3,
             24'b0, 104'h123456789ABCDEF00112233445},
             104'h123456789ABCDEF00112233445,
             32'd3, 32'd1200, 80'd50, 1'b1
        );

        // Teste 2: duracao esperada incorreta
        executar_teste(
            2,
            {16'b0, 80'd350, 16'b0, 80'd200, 32'd800, 32'd4,
             24'b0, 104'h11112222333344445555666677},
             104'h11112222333344445555666677,
             32'd4, 32'd800, 80'd100, 1'b0
        );

        // Teste 3: segundo registro valido
        executar_teste(
            3,
            {16'b0, 80'd1100, 16'b0, 80'd1000, 32'd2000, 32'd5,
             24'b0, 104'hABCDEF1234567890ABCDEF1234},
             104'hABCDEF1234567890ABCDEF1234,
             32'd5, 32'd2000, 80'd100, 1'b1
        );

        // Teste 4: quantidade de bytes esperada incorreta
        executar_teste(
            4,
            {16'b0, 80'd450, 16'b0, 80'd400, 32'd500, 32'd2,
             24'b0, 104'h55556666777788889999AAAABB},
             104'h55556666777788889999AAAABB,
             32'd2, 32'd1200, 80'd50, 1'b0
        );

        // Teste 5: chave esperada incorreta
        // A entrada e valida, mas a chave esperada e diferente.
        executar_teste(
            5,
            {16'b0, 80'd600, 16'b0, 80'd500, 32'd1000, 32'd6,
             24'b0, 104'h123456789ABCDEF00112233445},
             104'hFFFFFFFFFFFFFFFFFFFFFFFFFF,
             32'd6, 32'd1000, 80'd100, 1'b1
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
