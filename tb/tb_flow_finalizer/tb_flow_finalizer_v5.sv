// VERSÃO 5
// Adicionados conversões e simulações para mostragem de tempo "real" na simulação

`timescale 1ns/1ps

module tb_flow_finalizer_v5;

    logic clk;
    logic rst;
    logic fin_valid;
    logic [383:0] flow_entry;
    logic [247:0] feature_vector;
    logic fin_done;

    integer testes_ok;
    integer testes_erro_detectados;
    integer testes_falhos;

    // Timestamps calculados usando o relogio do computador.
    integer arquivo_hora;
    integer status_leitura;
    longint signed agora_unix;
    longint signed inicio_hoje_utc;
    longint signed inicio_ontem_utc;
    longint signed segundos_desde_meia_noite;
    logic [79:0] ts_inicial_1, ts_final_1;
    logic [79:0] ts_inicial_2, ts_final_2;
    logic [79:0] ts_inicial_3, ts_final_3;
    logic [79:0] ts_inicial_4, ts_final_4;
    logic [79:0] ts_inicial_5, ts_final_5;

    // Instância do modulo
    flow_finalizer_v5 dut (
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

    // Formata um valor de 0 a 99 com dois digitos.
    function automatic string dois_digitos(input integer valor);
        begin
            if (valor < 10)
                dois_digitos = {"0", $sformatf("%0d", valor)};
            else
                dois_digitos = $sformatf("%0d", valor);
        end
    endfunction

    // Convesão para ano/mês/dia/hora
    function automatic string data_hora_unix(input logic [79:0] timestamp);
        longint signed segundos_locais;
        longint signed dias;
        longint signed segundos_do_dia;
        longint signed z;
        longint signed era;
        longint signed doe;
        longint signed yoe;
        longint signed ano;
        longint signed doy;
        longint signed mp;
        longint signed mes;
        longint signed dia;
        integer hora;
        integer minuto;
        integer segundo;
        begin
            // Subtraindo 3 horas para exibir no fuso-horario de Brasilia.
            segundos_locais = $signed(timestamp[63:0]) - 10800;
            dias = segundos_locais / 86400;
            segundos_do_dia = segundos_locais % 86400;

            if (segundos_do_dia < 0) begin
                segundos_do_dia = segundos_do_dia + 86400;
                dias = dias - 1;
            end

            z = dias + 719468;
            era = z / 146097;
            doe = z - era * 146097;
            yoe = (doe - doe/1460 + doe/36524 - doe/146096) / 365;
            ano = yoe + era * 400;
            doy = doe - (365*yoe + yoe/4 - yoe/100);
            mp = (5*doy + 2) / 153;
            dia = doy - (153*mp + 2)/5 + 1;

            if (mp < 10)
                mes = mp + 3;
            else
                mes = mp - 9;

            if (mes <= 2)
                ano = ano + 1;

            hora = segundos_do_dia / 3600;
            minuto = (segundos_do_dia % 3600) / 60;
            segundo = segundos_do_dia % 60;

            data_hora_unix = $sformatf("%02d/%02d/%04d %s:%s:%s",
                                       dia, mes, ano,
                                       dois_digitos(hora),
                                       dois_digitos(minuto),
                                       dois_digitos(segundo));
        end
    endfunction

    // Exibe o timestamp e sua data/hora correspondente.
    task automatic mostrar_timestamp(
        input string descricao,
        input logic [79:0] timestamp
    );
        begin
            $display("%s: %s (horario de Brasilia)",
                     descricao, data_hora_unix(timestamp));
            $display("%s Tempo (segundos): %0d", descricao, timestamp);
        end
    endtask

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
            mostrar_timestamp("Timestamp inicial", entrada[271:192]);
            mostrar_timestamp("Timestamp final  ", entrada[367:288]);
            $display("Chave   : %h", feature_vector[247:144]);
            $display("Pacotes : %0d", feature_vector[143:112]);
            $display("Bytes   : %0d", feature_vector[111:80]);
            $display("Duracao : %0d segundos", feature_vector[79:0]);
            $display("Duracao : %s:%s:%s (HH:MM:SS)",
                     dois_digitos(feature_vector[79:0] / 3600),
                     dois_digitos((feature_vector[79:0] % 3600) / 60),
                     dois_digitos(feature_vector[79:0] % 60));

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
        $system("powershell -NoProfile -Command \"[DateTimeOffset]::UtcNow.ToUnixTimeSeconds() | Out-File -Encoding ascii current_epoch.txt\"");

        arquivo_hora = $fopen("current_epoch.txt", "r");
        if (arquivo_hora == 0) begin
            $display("ERRO: nao foi possivel ler current_epoch.txt.");
            $display("Verifique se o ModelSim consegue executar o PowerShell.");
            $finish;
        end

        status_leitura = $fscanf(arquivo_hora, "%d", agora_unix);
        $fclose(arquivo_hora);

        if (status_leitura != 1) begin
            $display("ERRO: nao foi possivel obter o horario atual.");
            $finish;
        end

        // Para calcular a meia-noite de hoje no horario de Brasilia / troca de dia - ontem/hoje.
        segundos_desde_meia_noite = (agora_unix - 10800) % 86400;
        inicio_hoje_utc = agora_unix - segundos_desde_meia_noite;
        inicio_ontem_utc = inicio_hoje_utc - 86400;

        // Para usar horario ao longo do dia anterior ao dia atual do computador.
        ts_inicial_1 = inicio_ontem_utc + 8*3600;
        ts_final_1   = ts_inicial_1 + 50;

        // Para usar horario ao longo do dia anterior ao dia atual do computador.
		ts_inicial_2 = inicio_ontem_utc + 14*3600;
        ts_final_2   = ts_inicial_2 + 150;

		// Para usar horario ao longo do dia atual com horario menor ao atual do computador.
        ts_inicial_3 = inicio_hoje_utc + segundos_desde_meia_noite/3;
        ts_final_3   = ts_inicial_3 + 100;

        // Para usar horario ao longo do dia atual com horario menor ao atual do computador.
		ts_final_4   = inicio_hoje_utc + (segundos_desde_meia_noite*2)/3;
        ts_inicial_4 = ts_final_4 - 50;

        // O ultimo teste para terminar no horario atual da simulacao no Model Sim
        ts_final_5   = agora_unix;
        ts_inicial_5 = agora_unix - 100;


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
            {16'b0, ts_final_1, 16'b0, ts_inicial_1, 32'd1200, 32'd3,
             24'b0, 104'h123456789ABCDEF00112233445},
             104'h123456789ABCDEF00112233445,
             32'd3, 32'd1200, 80'd50, 1'b1
        );

        // Teste 2: duracao esperada incorreta
        executar_teste(
            2,
            {16'b0, ts_final_2, 16'b0, ts_inicial_2, 32'd800, 32'd4,
             24'b0, 104'h11112222333344445555666677},
             104'h11112222333344445555666677,
             32'd4, 32'd800, 80'd100, 1'b0
        );

        // Teste 3: segundo registro valido
        executar_teste(
            3,
            {16'b0, ts_final_3, 16'b0, ts_inicial_3, 32'd2000, 32'd5,
             24'b0, 104'hABCDEF1234567890ABCDEF1234},
             104'hABCDEF1234567890ABCDEF1234,
             32'd5, 32'd2000, 80'd100, 1'b1
        );

        // Teste 4: quantidade de bytes esperada incorreta
        executar_teste(
            4,
            {16'b0, ts_final_4, 16'b0, ts_inicial_4, 32'd500, 32'd2,
             24'b0, 104'h55556666777788889999AAAABB},
             104'h55556666777788889999AAAABB,
             32'd2, 32'd1200, 80'd50, 1'b0
        );

        // Teste 5: chave esperada incorreta
        // A entrada e valida, mas a chave esperada e diferente.
        executar_teste(
            5,
            {16'b0, ts_final_5, 16'b0, ts_inicial_5, 32'd1000, 32'd6,
             24'b0, 104'h123456789ABCDEF00112233445},
             104'hFFFFFFFFFFFFFFFFFFFFFFFFFF,
             32'd6, 32'd1000, 80'd100, 1'b0
        );

        $display("");
        $display("--------------------------------");
        $display("RESUMO DOS TESTES");
        $display("--------------------------------");
        $display("Testes corretos: %0d", testes_ok);
        $display("Erros esperados: %0d", testes_erro_detectados);
        $display("Testes com falha: %0d", testes_falhos);

        $finish;
    end

endmodule
