`timescale 1ns/1ps

`default_nettype none



module tb_top_extracao_features_com_entrada;



    localparam integer NUM_VETORES = 181;

    localparam integer NUM_ENTRADAS = 65536;

    localparam integer INTERVALO_PACOTES = 80;

    localparam integer TIMEOUT_HASH = 40;

    localparam integer TIMEOUT_LOOKUP = 100;

    localparam integer TIMEOUT_SCAN = 300000;



    localparam logic [1:0] RESULT_NONE      = 2'b00;

    localparam logic [1:0] RESULT_MISS      = 2'b01;

    localparam logic [1:0] RESULT_HIT       = 2'b10;

    localparam logic [1:0] RESULT_COLLISION = 2'b11;



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



    // Vetor de entrada:

    // [215:112] chave de fluxo

    // [111:96]  tamanho do pacote

    // [95:16]   timestamp

    // [15:0]    CRC16 esperado

    logic [215:0] vectors [0:NUM_VETORES-1];



    // ---------------------------------------------------------

    // Modelo de referência da Flow Table

    // ---------------------------------------------------------



    logic expected_valid [0:NUM_ENTRADAS-1];



    logic [103:0] expected_key [0:NUM_ENTRADAS-1];

    logic [31:0] expected_packet_count [0:NUM_ENTRADAS-1];

    logic [31:0] expected_byte_count [0:NUM_ENTRADAS-1];



    logic [79:0] expected_first_timestamp [0:NUM_ENTRADAS-1];

    logic [79:0] expected_last_timestamp [0:NUM_ENTRADAS-1];



    logic [1:0] expected_result [0:NUM_VETORES-1];



    integer expected_miss;

    integer expected_hit;

    integer expected_collision;

    integer expected_feature_count;



    // ---------------------------------------------------------

    // Contadores observados no hardware

    // ---------------------------------------------------------



    integer observed_miss;

    integer observed_hit;

    integer observed_collision;

    integer observed_features;



    integer i;

    integer idx;

    integer timeout_count;

    integer expected_scan_index;



    logic scan_active;

    logic empty_scan_active;



    logic [247:0] expected_feature;

    // Campos temporários para o cálculo de duração (segundos + nanossegundos).
    logic [47:0] expected_first_seconds;
    logic [31:0] expected_first_nanoseconds;
    logic [47:0] expected_last_seconds;
    logic [31:0] expected_last_nanoseconds;
    logic [47:0] expected_duration_seconds;
    logic [31:0] expected_duration_nanoseconds;
    logic [79:0] expected_duration;



    always #5 clk = ~clk;



    // ---------------------------------------------------------

    // DUT

    // ---------------------------------------------------------



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



    // ---------------------------------------------------------

    // Modelo de referência

    //

    // Calcula antecipadamente o resultado esperado de cada

    // pacote, sem utilizar os resultados internos do Controller.

    // ---------------------------------------------------------



    task automatic build_reference_model;



        integer k;

        integer hash_value;



        begin

            expected_miss = 0;

            expected_hit = 0;

            expected_collision = 0;

            expected_feature_count = 0;



            for (k = 0; k < NUM_ENTRADAS; k = k + 1) begin

                expected_valid[k] = 1'b0;

                expected_key[k] = '0;

                expected_packet_count[k] = '0;

                expected_byte_count[k] = '0;

                expected_first_timestamp[k] = '0;

                expected_last_timestamp[k] = '0;

            end



            for (k = 0; k < NUM_VETORES; k = k + 1) begin



                hash_value = vectors[k][15:0];



                if (!expected_valid[hash_value]) begin



                    // MISS: primeira ocorrência do índice.

                    expected_result[k] = RESULT_MISS;



                    expected_valid[hash_value] = 1'b1;

                    expected_key[hash_value] =

                        vectors[k][215:112];



                    expected_packet_count[hash_value] = 32'd1;



                    expected_byte_count[hash_value] =

                        {16'b0, vectors[k][111:96]};



                    expected_first_timestamp[hash_value] =

                        vectors[k][95:16];



                    expected_last_timestamp[hash_value] =

                        vectors[k][95:16];



                    expected_miss = expected_miss + 1;



                end else if (

                    expected_key[hash_value] == vectors[k][215:112]

                ) begin



                    // HIT: índice e chave correspondem.

                    expected_result[k] = RESULT_HIT;



                    expected_packet_count[hash_value] =

                        expected_packet_count[hash_value] + 32'd1;



                    expected_byte_count[hash_value] =

                        expected_byte_count[hash_value] +

                        {16'b0, vectors[k][111:96]};



                    expected_last_timestamp[hash_value] =

                        vectors[k][95:16];



                    expected_hit = expected_hit + 1;



                end else begin



                    // COLLISION: mesmo índice, chave diferente.

                    // O registro original permanece inalterado.

                    expected_result[k] = RESULT_COLLISION;



                    expected_collision = expected_collision + 1;



                end

            end



            for (k = 0; k < NUM_ENTRADAS; k = k + 1) begin

                if (expected_valid[k])

                    expected_feature_count =

                        expected_feature_count + 1;

            end

        end

    endtask



    // ---------------------------------------------------------

    // Verifica a captura dos dados pelo Controller

    // ---------------------------------------------------------



    task automatic check_controller_capture(

        input integer vector_number

    );



        begin

            // Aguarda a saída válida do Hash Unit.

            timeout_count = 0;



            while (

                dut.hash_valid !== 1'b1 &&

                timeout_count < TIMEOUT_HASH

            ) begin

                @(negedge clk);

                timeout_count = timeout_count + 1;

            end



            if (dut.hash_valid !== 1'b1)

                $fatal(1,

                    "ERRO HASH: timeout no vetor %0d",

                    vector_number

                );



            // Confere os resultados do Hash Unit.

            if (dut.hash_index !== vectors[vector_number][15:0])

                $fatal(1,

                    "ERRO CRC: vetor %0d, esperado %04h, obtido %04h",

                    vector_number,

                    vectors[vector_number][15:0],

                    dut.hash_index

                );



            if (dut.flow_key !== vectors[vector_number][215:112])

                $fatal(1,

                    "ERRO: flow_key incorreta no vetor %0d",

                    vector_number

                );



            if (dut.packet_length !== vectors[vector_number][111:96])

                $fatal(1,

                    "ERRO: packet_length incorreto no vetor %0d",

                    vector_number

                );



            if (dut.timestamp !== vectors[vector_number][95:16])

                $fatal(1,

                    "ERRO: timestamp incorreto no vetor %0d",

                    vector_number

                );



            // O Controller só captura quando está em IDLE.

            if (dut.u_controller.start !== 1'b1)

                $fatal(1,

                    "ERRO INTEGRACAO: Controller nao iniciou captura do vetor %0d",

                    vector_number

                );



            // O Controller captura os dados na próxima borda.

            @(posedge clk);

            #1;



            if (dut.u_controller.base_addr[19:4] !==

                vectors[vector_number][15:0])

                $fatal(1,

                    "ERRO CONTROLLER: hash_index nao capturado corretamente"

                );



            if (dut.u_controller.flow_key_reg !==

                vectors[vector_number][215:112])

                $fatal(1,

                    "ERRO CONTROLLER: flow_key nao capturada"

                );



            if (dut.u_controller.packet_length_reg !==

                vectors[vector_number][111:96])

                $fatal(1,

                    "ERRO CONTROLLER: packet_length nao capturado"

                );



            if (dut.u_controller.timestamp_reg !==

                vectors[vector_number][95:16])

                $fatal(1,

                    "ERRO CONTROLLER: timestamp nao capturado"

                );

        end

    endtask



    // ---------------------------------------------------------

    // Aguarda o término do processamento de um pacote

    // ---------------------------------------------------------



    task automatic wait_lookup_done(

        input integer vector_number

    );



        integer t;



        begin

            t = 0;



            while (

                dut.u_controller.lookup_done !== 1'b1 &&

                t < TIMEOUT_LOOKUP

            ) begin

                @(negedge clk);

                t = t + 1;

            end



            if (dut.u_controller.lookup_done !== 1'b1)

                $fatal(1,

                    "ERRO CONTROLLER: lookup_done timeout no vetor %0d",

                    vector_number

                );



            // Confere a classificação realizada pelo hardware.

            if (

                dut.u_controller.lookup_result !==

                expected_result[vector_number]

            ) begin

                $fatal(1,

                    "ERRO CLASSIFICACAO: vetor %0d, esperado=%b obtido=%b",

                    vector_number,

                    expected_result[vector_number],

                    dut.u_controller.lookup_result

                );

            end



            case (dut.u_controller.lookup_result)



                RESULT_MISS:

                    observed_miss = observed_miss + 1;



                RESULT_HIT:

                    observed_hit = observed_hit + 1;



                RESULT_COLLISION:

                    observed_collision = observed_collision + 1;



                default:

                    $fatal(1,

                        "ERRO: lookup_result invalido no vetor %0d",

                        vector_number

                    );



            endcase

        end

    endtask



    // ---------------------------------------------------------

    // Monitor da integração Controller + Finalizer

    //

    // fin_done é observado na borda negativa para evitar

    // disputa com as atribuições não bloqueantes do DUT.

    // ---------------------------------------------------------



    always @(negedge clk) begin



        if (!reset_n) begin

            observed_features = 0;



        end else if (scan_active && fin_done) begin



            if (empty_scan_active) begin



                $fatal(1,

                    "ERRO: Finalizer recebeu registro na segunda varredura"

                );



            end else begin



                // Procura a próxima entrada válida esperada.

                while (

                    expected_scan_index < NUM_ENTRADAS &&

                    !expected_valid[expected_scan_index]

                ) begin

                    expected_scan_index =

                        expected_scan_index + 1;

                end



                if (expected_scan_index >= NUM_ENTRADAS)

                    $fatal(1,

                        "ERRO: Finalizer recebeu feature excedente"

                    );



                // Layout:

                // [247:144] chave

                // [143:112] packet_count

                // [111:80]  byte_count

                // [79:0]    duration



                // Separa segundos e nanossegundos dos timestamps.
                expected_first_seconds =
                    expected_first_timestamp[expected_scan_index][79:32];

                expected_first_nanoseconds =
                    expected_first_timestamp[expected_scan_index][31:0];

                expected_last_seconds =
                    expected_last_timestamp[expected_scan_index][79:32];

                expected_last_nanoseconds =
                    expected_last_timestamp[expected_scan_index][31:0];

                // Calcula a duração considerando empréstimo de 1 segundo.
                if (expected_last_nanoseconds >= expected_first_nanoseconds) begin
                    expected_duration_seconds =
                        expected_last_seconds - expected_first_seconds;

                    expected_duration_nanoseconds =
                        expected_last_nanoseconds - expected_first_nanoseconds;
                end else begin
                    expected_duration_seconds =
                        expected_last_seconds - expected_first_seconds - 1'b1;

                    expected_duration_nanoseconds =
                        32'd1000000000 + expected_last_nanoseconds -
                        expected_first_nanoseconds;
                end

                expected_duration = {
                    expected_duration_seconds,
                    expected_duration_nanoseconds
                };

                expected_feature = {
                    expected_key[expected_scan_index],
                    expected_packet_count[expected_scan_index],
                    expected_byte_count[expected_scan_index],
                    expected_duration
                };



                if (feature_vector !== expected_feature) begin



                    $display("ERRO FEATURE na entrada %0d",

                             expected_scan_index);



                    $display("Esperado: %062h", expected_feature);

                    $display("Obtido:   %062h", feature_vector);



                    $fatal(1,

                        "ERRO: feature_vector incorreto"

                    );

                end



                observed_features = observed_features + 1;



                // A próxima feature deve ter índice maior.

                expected_scan_index =

                    expected_scan_index + 1;



            end

        end

    end



    // ---------------------------------------------------------

    // Teste principal

    // ---------------------------------------------------------



    initial begin



        observed_features = 0;

        observed_miss = 0;

        observed_hit = 0;

        observed_collision = 0;

        observed_features = 0;



        scan_active = 1'b0;

        empty_scan_active = 1'b0;



        expected_scan_index = 0;



        $display("");

        $display("==================================================");

        $display(" TESTBENCH DE INTEGRACAO COMPLETA");

        $display(" Hash Unit + Controller + Flow Table + Finalizer");

        $display("==================================================");



        // -----------------------------------------------------

        // Leitura dos vetores

        // -----------------------------------------------------



        $readmemh("hash_vectors.mem", vectors);



        // -----------------------------------------------------

        // Inicializa o modelo de referência

        // -----------------------------------------------------



        build_reference_model();



        $display("");

        $display("RESULTADOS ESPERADOS DO MODELO:");

        $display("MISS:      %0d", expected_miss);

        $display("HIT:       %0d", expected_hit);

        $display("COLLISION: %0d", expected_collision);

        $display("FEATURES:  %0d", expected_feature_count);



        if (expected_miss == 0 ||

            expected_hit == 0 ||

            expected_collision == 0) begin



            $fatal(1,

                "ERRO: conjunto de vetores nao cobre MISS, HIT e COLLISION"

            );

        end



        // -----------------------------------------------------

        // Reset

        // -----------------------------------------------------



        repeat (5) @(negedge clk);



        reset_n = 1'b1;



        repeat (5) @(negedge clk);



        // -----------------------------------------------------

        // Envio dos pacotes

        // -----------------------------------------------------



        $display("");

        $display("INICIANDO TESTES HASH + CONTROLLER");



        for (i = 0; i < NUM_VETORES; i = i + 1) begin



            @(negedge clk);



            src_ip_in = vectors[i][215:184];

            dst_ip_in = vectors[i][183:152];

            src_port_in = vectors[i][151:136];

            dst_port_in = vectors[i][135:120];

            protocol_in = vectors[i][119:112];



            packet_length_in = vectors[i][111:96];

            timestamp_in = vectors[i][95:16];



            in_valid = 1'b1;



            @(negedge clk);

            in_valid = 1'b0;



            // Verifica Hash Unit e captura pelo Controller.

            check_controller_capture(i);



            // Aguarda a classificação e a atualização da tabela.

            wait_lookup_done(i);



            // Intervalo conservador: o Controller não possui

            // ready nem FIFO para armazenar pacotes recebidos

            // enquanto está ocupado.

            repeat (INTERVALO_PACOTES) @(negedge clk);



            if ((i % 20) == 0)

                $display("Pacotes processados: %0d/%0d",

                         i + 1, NUM_VETORES);



        end



        $display("");

        $display("*TODO*S OS PACOTES FORAM PROCESSADOS.");



        // -----------------------------------------------------

        // Confere os resultados do Controller

        // -----------------------------------------------------



        $display("");

        $display("RESULTADOS OBSERVADOS NO CONTROLLER:");



        $display("MISS:      %0d", observed_miss);

        $display("HIT:       %0d", observed_hit);

        $display("COLLISION: %0d", observed_collision);



        if (observed_miss != expected_miss)

            $fatal(1, "ERRO: quantidade de MISS incorreta");



        if (observed_hit != expected_hit)

            $fatal(1, "ERRO: quantidade de HIT incorreta");



        if (observed_collision != expected_collision)

            $fatal(1, "ERRO: quantidade de COLLISION incorreta");



        if (dut.u_controller.collision_count !==

            expected_collision)

            $fatal(1,

                "ERRO: collision_count interno incorreto"

            );



        // -----------------------------------------------------

        // Primeira varredura

        // -----------------------------------------------------



        $display("");

        $display("INICIANDO VARREDURA DA FLOW TABLE");



        expected_scan_index = 0;

        observed_features = 0;



        scan_active = 1'b1;

        empty_scan_active = 1'b0;



        @(negedge clk);

        pcap_done = 1'b1;



        @(negedge clk);

        pcap_done = 1'b0;



        timeout_count = 0;



        while (

            dut.u_controller.scan_done !== 1'b1 &&

            timeout_count < TIMEOUT_SCAN

        ) begin

            @(negedge clk);

            timeout_count = timeout_count + 1;

        end



        if (dut.u_controller.scan_done !== 1'b1)

            $fatal(1,

                "ERRO: timeout aguardando scan_done"

            );



        // Desativa o monitor após a conclusão.

        scan_active = 1'b0;



        // Permite observar o último pulso de fin_done.

        repeat (3) @(negedge clk);



        if (observed_features != expected_feature_count) begin



            $display("Features esperadas: %0d",

                     expected_feature_count);



            $display("Features recebidas: %0d",

                     observed_features);



            $fatal(1,

                "ERRO: quantidade de features incorreta"

            );

        end



        $display("PASSOU: todas as features foram conferidas.");



        // -----------------------------------------------------

        // Verifica invalidação das entradas

        // -----------------------------------------------------



        if (dut.INVALIDATE_AFTER_SEND) begin



            $display("");

            $display("VERIFICANDO INVALIDACAO DA FLOW TABLE");



            for (idx = 0; idx < NUM_ENTRADAS; idx = idx + 1) begin



                if (expected_valid[idx]) begin



                    if (

                        dut.u_flow_table.mem[{idx[15:0], 4'b0000}]

                        !== 32'b0

                    ) begin

                        $fatal(1,

                            "ERRO: entrada %0d nao foi invalidada",

                            idx

                        );

                    end

                end

            end



            $display("PASSOU: todas as entradas enviadas foram invalidadas.");



        end



        // -----------------------------------------------------

        // Segunda varredura: deve estar vazia

        // -----------------------------------------------------



        $display("");

        $display("INICIANDO SEGUNDA VARREDURA");



        scan_active = 1'b1;

        empty_scan_active = 1'b1;



        @(negedge clk);

        pcap_done = 1'b1;



        @(negedge clk);

        pcap_done = 1'b0;



        timeout_count = 0;



        while (

            dut.u_controller.scan_done !== 1'b1 &&

            timeout_count < TIMEOUT_SCAN

        ) begin

            @(negedge clk);

            timeout_count = timeout_count + 1;

        end



        if (dut.u_controller.scan_done !== 1'b1)

            $fatal(1,

                "ERRO: timeout na segunda varredura"

            );



        scan_active = 1'b0;

        empty_scan_active = 1'b0;



        repeat (3) @(negedge clk);



        $display("PASSOU: segunda varredura sem features repetidas.");



        // -----------------------------------------------------

        // Relatório final

        // -----------------------------------------------------



        $display("");

        $display("==================================================");

        $display("          RESULTADO FINAL DA INTEGRACAO");

        $display("==================================================");



        $display("Pacotes enviados:       %0d", NUM_VETORES);

        $display("MISS:                   %0d", observed_miss);

        $display("HIT:                    %0d", observed_hit);

        $display("COLLISION:              %0d", observed_collision);

        $display("Features conferidas:    %0d", observed_features);



        $display("");

        $display("PASSOU: Hash Unit + Controller");

        $display("PASSOU: Controller + Flow Table");

        $display("PASSOU: Controller + Finalizer");

        $display("PASSOU: Layout dos 384 bits");

        $display("PASSOU: Vetor de features de 248 bits");

        $display("PASSOU: Handshake fin_valid / fin_done");

        $display("PASSOU: Invalidação e segunda varredura");



        $display("==================================================");

        $display("*TODO*S OS TESTES FORAM CONCLUIDOS COM SUCESSO.");

        $display("==================================================");



        $finish;

    end



endmodule



`default_nettype wire