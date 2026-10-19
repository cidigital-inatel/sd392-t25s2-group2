`timescale 1ns/1ps

module tb_flow_finalizer;

    logic clk;
    logic rst;
    logic finalize_en;

    logic [383:0] flow_entry;
    logic [279:0] feature_vector;
    logic finalize_done;

    integer testes_ok;
    integer testes_erro_detectados;

    // Instância do módulo
	flow_finalizer dut (
        .clk            (clk),
        .rst            (rst),
        .finalize_en    (finalize_en),
        .flow_entry     (flow_entry),
        .feature_vector (feature_vector),
        .finalize_done  (finalize_done)
    );

    // Geração do clock de 10 ns
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Para aplicar os valores e conferir o resultado
    task automatic executar_teste(
        input integer numero,
        input [383:0] entrada,
        input [63:0] chave_esperada,
        input [19:0] pacotes_esperados,
        input [30:0] bytes_esperados,
        input [47:0] duracao_esperada,
        input bit teste_deve_passar
    );

        reg resultado_correto;

        begin
            @(negedge clk);
            flow_entry = entrada;
            finalize_en = 1'b1;

            @(posedge clk);
            #1;

            resultado_correto =
                (feature_vector[258:195] == chave_esperada) &&
                (feature_vector[194:175] == pacotes_esperados) &&
                (feature_vector[174:144] == bytes_esperados) &&
                (feature_vector[47:0] == duracao_esperada) &&
                (finalize_done == 1'b1);

            $display("");
            $display("--------------------------------");
            $display("TESTE %0d", numero);
            $display("--------------------------------");

            $display("Chave        : %h", feature_vector[258:195]);
            $display("Pacotes      : %0d", feature_vector[194:175]);
            $display("Bytes        : %0d", feature_vector[174:144]);
            $display("Duracao      : %0d", feature_vector[47:0]);

            if (teste_deve_passar) begin
                if (resultado_correto) begin
                    $display("TESTE OK: valores corretos.");
                    testes_ok = testes_ok + 1;
                end else begin
                    $display("FALHA: valores diferentes do esperado.");
                end
            end else begin
                if (!resultado_correto) begin
                    $display("TESTE OK: diferenca identificada.");
                    testes_erro_detectados = testes_erro_detectados + 1;
                end else begin
                    $display("FALHA: diferenca nao identificada.");
                end
            end

            @(negedge clk);
            finalize_en = 1'b0;
        end
    endtask

    initial begin
        rst = 1'b1;
        finalize_en = 1'b0;
        flow_entry = '0;

        testes_ok = 0;
        testes_erro_detectados = 0;

        repeat (2) @(negedge clk);
        rst = 1'b0;

        // Teste 1: 1º registro válido
        executar_teste(
            1,
            {173'b0, 64'h123456789ABCDEF0,
             20'd3, 31'd1200, 48'd100, 48'd150},
            64'h123456789ABCDEF0,
            20'd3, 31'd1200, 48'd50,
            1'b1
        );

        // Teste 2: duração esperada incorreta
        executar_teste(
            2,
            {173'b0, 64'h1111222233334444,
             20'd4, 31'd800, 48'd200, 48'd350},
            64'h1111222233334444,
            20'd4, 31'd800, 48'd100,
            1'b0
        );
		
		// Teste 3: 2º registro valido
        executar_teste(
            3,
            {173'b0, 64'hABCDEF1234567890,
             20'd5, 31'd2000, 48'd1000, 48'd1100},
            64'hABCDEF1234567890,
            20'd5, 31'd2000, 48'd100,
            1'b1
        );

        // Teste 4: quantidade de bytes esperada incorreta
        executar_teste(
            4,
            {173'b0, 64'h5555666677778888,
             20'd2, 31'd500, 48'd400, 48'd450},
            64'h5555666677778888,
            20'd2, 31'd1200, 48'd50,
            1'b0
        );

        $display("");
        $display("--------------------------------");
        $display("RESUMO DOS TESTES");
        $display("--------------------------------");
        $display("Testes corretos : %0d", testes_ok);
        $display("Erros detectados: %0d", testes_erro_detectados);

        $finish;
    end

endmodule
