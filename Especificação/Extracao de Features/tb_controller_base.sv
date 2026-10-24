`timescale 1ns/1ps

module tb_controller;

    localparam logic [1:0] RESULT_MISS      = 2'b01;
    localparam logic [1:0] RESULT_HIT       = 2'b10;
    localparam logic [1:0] RESULT_COLLISION = 2'b11;

    localparam logic [103:0] KEY_A = 104'h123456789ABCDEF123456789AB;
    localparam logic [103:0] KEY_B = 104'h00000000000000000000000001;

    logic clk = 1'b0;
    logic rst = 1'b1;

    logic [15:0]  hash_index;
    logic [103:0] flow_key;
    logic [15:0]  packet_length;
    logic [79:0]  timestamp;
    logic         hash_valid;

    logic         rd_en, rd_valid, wr_en, wr_done;
    logic [19:0]  rd_addr, wr_addr;
    logic [31:0]  rd_data, wr_data;

    logic [383:0] flow_entry;
    logic [31:0]  collision_count;
    logic         scan_done;
    logic         fin_valid;
    logic         fin_done;
    logic [1:0]   lookup_result;
    logic         lookup_done;

    integer read_count  = 0;
    integer write_count = 0;
    integer start_count = 0;
    integer done_count  = 0;
    integer errors      = 0;
    integer coll_expected = 0;   // colisoes esperadas ate o momento

    logic [15:0] cur_idx = '0;
    logic        start_q = 1'b0;

    assign fin_done = 1'b0;   // Finalizer nao faz parte desta etapa

    always #5 clk = ~clk;

    controller dut (
        .clk(clk), .rst(rst),
        .hash_index(hash_index), .flow_key(flow_key),
        .packet_length(packet_length), .timestamp(timestamp),
        .hash_valid(hash_valid),
        .rd_en(rd_en), .rd_addr(rd_addr),
        .rd_data(rd_data), .rd_valid(rd_valid),
        .wr_en(wr_en), .wr_addr(wr_addr),
        .wr_data(wr_data), .wr_done(wr_done),
        .flow_entry(flow_entry),
        .fin_valid(fin_valid), .fin_done(fin_done),
        .pcap_done(1'b0)
    );

    // Sinais internos do Controller (fora da interface), lidos por referencia hierarquica
    assign lookup_result   = dut.lookup_result;
    assign lookup_done     = dut.lookup_done;
    assign collision_count = dut.collision_count;
    assign scan_done       = dut.scan_done;

    // Porta de escrita do testbench (pre-carga da memoria).
    // So e usada com o Controller em IDLE.
    logic        tb_wr_en   = 1'b0;
    logic [19:0] tb_wr_addr = '0;
    logic [31:0] tb_wr_data = '0;

    wire         ft_wr_en   = tb_wr_en | wr_en;
    wire [19:0]  ft_wr_addr = tb_wr_en ? tb_wr_addr : wr_addr;
    wire [31:0]  ft_wr_data = tb_wr_en ? tb_wr_data : wr_data;

    flow_table ft (
        .clk(clk), .rst(rst),
        .rd_en(rd_en), .rd_addr(rd_addr),
        .rd_data(rd_data), .rd_valid(rd_valid),
        .wr_en(ft_wr_en), .wr_addr(ft_wr_addr),
        .wr_data(ft_wr_data), .wr_done(wr_done)
    );

    // ---------------- Monitores ----------------
    always @(posedge clk) begin
        if (!rst) begin
            if (rd_en)       read_count  <= read_count + 1;
            if (wr_en)       write_count <= write_count + 1;
            if (dut.start)   start_count <= start_count + 1;
            if (lookup_done) done_count  <= done_count + 1;

            // Todo acesso deve ficar dentro das 16 palavras da entrada
            if ((rd_en && rd_addr[19:4] !== cur_idx) ||
                (wr_en && wr_addr[19:4] !== cur_idx)) begin
                $error("Acesso fora da entrada %0d (rd=%0d wr=%0d)",
                       cur_idx, rd_addr, wr_addr);
                errors = errors + 1;
            end

            // Leitura com X: memoria nao inicializada
            if (rd_valid && $isunknown(rd_data)) begin
                $error("rd_data desconhecido (X): memoria nao inicializada?");
                errors = errors + 1;
            end

            // start deve ser um pulso de 1 ciclo
            start_q <= dut.start;
            if (dut.start && start_q) begin
                $error("start durou mais de 1 ciclo");
                errors = errors + 1;
            end
        end
    end

    // ---------------- Tasks ----------------
    task automatic clear_counters;
        begin
            read_count  = 0;
            write_count = 0;
            start_count = 0;
            done_count  = 0;
        end
    endtask

    // Pacote com hash_valid de 1 ciclo
    task automatic send_packet(
        input logic [15:0]  idx,
        input logic [103:0] key,
        input logic [15:0]  length_bytes,
        input logic [79:0]  ts
    );
        begin
            @(negedge clk);
            cur_idx       = idx;
            hash_index    = idx;
            flow_key      = key;
            packet_length = length_bytes;
            timestamp     = ts;
            hash_valid    = 1'b1;

            @(negedge clk);
            hash_valid    = 1'b0;
            // Embaralha as entradas: o Controller ja deve ter capturado tudo
            hash_index    = $urandom;
            flow_key      = {$urandom, $urandom, $urandom, $urandom};
            packet_length = $urandom;
            timestamp     = {$urandom, $urandom, $urandom};
        end
    endtask

    // Espera o pulso de lookup_done e mais um ciclo (para os contadores
    // dos monitores atualizarem)
    task automatic wait_done;
        integer timeout;
        begin
            timeout = 0;
            while (lookup_done !== 1'b1 && timeout < 2000) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            if (timeout >= 2000)
                $fatal(1, "TIMEOUT esperando lookup_done");
            @(negedge clk);
        end
    endtask

    task automatic check_word(
        input logic [19:0] address,
        input logic [31:0] expected,
        input string       label
    );
        begin
            if (ft.mem[address] !== expected) begin
                $error("FALHA %s: end=%0d esperado=%h obtido=%h",
                       label, address, expected, ft.mem[address]);
                errors = errors + 1;
            end
        end
    endtask

    // Confere o registro completo W0..W12
    task automatic check_entry(
        input logic [15:0]  idx,
        input logic [103:0] key,
        input logic [31:0]  pkts,
        input logic [31:0]  bytes,
        input logic [79:0]  first_ts,
        input logic [79:0]  last_ts
    );
        begin
            check_word({idx, 4'd0},  32'd1,                    "W0 valid");
            check_word({idx, 4'd1},  key[31:0],                "W1 key[31:0]");
            check_word({idx, 4'd2},  key[63:32],               "W2 key[63:32]");
            check_word({idx, 4'd3},  key[95:64],               "W3 key[95:64]");
            check_word({idx, 4'd4},  {24'b0, key[103:96]},     "W4 key[103:96]");
            check_word({idx, 4'd5},  pkts,                     "W5 packet_count");
            check_word({idx, 4'd6},  bytes,                    "W6 byte_count");
            check_word({idx, 4'd7},  first_ts[31:0],           "W7 first_ts");
            check_word({idx, 4'd8},  first_ts[63:32],          "W8 first_ts");
            check_word({idx, 4'd9},  {16'b0, first_ts[79:64]}, "W9 first_ts");
            check_word({idx, 4'd10}, last_ts[31:0],            "W10 last_ts");
            check_word({idx, 4'd11}, last_ts[63:32],           "W11 last_ts");
            check_word({idx, 4'd12}, {16'b0, last_ts[79:64]},  "W12 last_ts");
        end
    endtask

    // Escreve uma palavra na Flow Table pela porta de escrita (Controller em IDLE)
    task automatic poke(
        input logic [19:0] addr,
        input logic [31:0] data
    );
        begin
            @(negedge clk);
            tb_wr_en   = 1'b1;
            tb_wr_addr = addr;
            tb_wr_data = data;
            @(negedge clk);
            tb_wr_en   = 1'b0;
        end
    endtask

    // Pre-carrega valid e flow_key (com lixo opcional em W4[31:8])
    task automatic preload(
        input logic [15:0]  idx,
        input logic [31:0]  w0,
        input logic [103:0] key,
        input logic [23:0]  w4_junk
    );
        begin
            poke({idx, 4'd0}, w0);
            poke({idx, 4'd1}, key[31:0]);
            poke({idx, 4'd2}, key[63:32]);
            poke({idx, 4'd3}, key[95:64]);
            poke({idx, 4'd4}, {w4_junk, key[103:96]});
        end
    endtask

    // Confere resultado, leituras, escritas e pulsos de start / lookup_done
    task automatic check_run(
        input string  name,
        input logic [1:0] exp_res,
        input integer exp_rd,
        input integer exp_wr
    );
        begin
            if (lookup_result !== exp_res) begin
                $error("%s: resultado=%b esperado=%b", name, lookup_result, exp_res);
                errors = errors + 1;
            end
            if (read_count != exp_rd) begin
                $error("%s: leituras=%0d esperado=%0d", name, read_count, exp_rd);
                errors = errors + 1;
            end
            if (write_count != exp_wr) begin
                $error("%s: escritas=%0d esperado=%0d", name, write_count, exp_wr);
                errors = errors + 1;
            end
            if (start_count != 1) begin
                $error("%s: pulsos de start=%0d esperado=1", name, start_count);
                errors = errors + 1;
            end
            if (done_count != 1) begin
                $error("%s: pulsos de lookup_done=%0d esperado=1", name, done_count);
                errors = errors + 1;
            end

            // Contador de colisoes: soma 1 em cada COLLISION e nao muda nos demais
            if (exp_res == RESULT_COLLISION)
                coll_expected = coll_expected + 1;
            if (collision_count !== coll_expected) begin
                $error("%s: collision_count=%0d esperado=%0d", name,
                       collision_count, coll_expected);
                errors = errors + 1;
            end
        end
    endtask

    // Cenario padrao: hash_valid de 1 ciclo
    task automatic run_case(
        input string        name,
        input logic [15:0]  idx,
        input logic [103:0] key,
        input logic [15:0]  len,
        input logic [79:0]  ts,
        input logic [1:0]   exp_res,
        input integer       exp_rd,
        input integer       exp_wr
    );
        integer e0;
        begin
            e0 = errors;
            clear_counters();

            send_packet(idx, key, len, ts);
            wait_done();

            check_run(name, exp_res, exp_rd, exp_wr);

            if (errors == e0)
                $display("PASSOU: %s", name);
        end
    endtask

    // hash_valid mantido em nivel alto por 'hold' ciclos (mais longo que a
    // operacao). Deve gerar UMA unica operacao; os dados mudam depois do
    // primeiro ciclo para provar que a captura ocorreu uma vez so.
    task automatic run_held_case(
        input string        name,
        input logic [15:0]  idx,
        input logic [103:0] key,
        input logic [15:0]  len,
        input logic [79:0]  ts,
        input logic [1:0]   exp_res,
        input integer       exp_rd,
        input integer       exp_wr,
        input integer       hold
    );
        integer e0;
        begin
            e0 = errors;
            clear_counters();

            @(negedge clk);
            cur_idx       = idx;
            hash_index    = idx;
            flow_key      = key;
            packet_length = len;
            timestamp     = ts;
            hash_valid    = 1'b1;

            @(negedge clk);
            hash_index    = $urandom;
            flow_key      = {$urandom, $urandom, $urandom, $urandom};
            packet_length = $urandom;
            timestamp     = {$urandom, $urandom, $urandom};

            repeat (hold) @(negedge clk);   // valid continua em 1
            hash_valid = 1'b0;
            repeat (10) @(negedge clk);

            check_run(name, exp_res, exp_rd, exp_wr);

            if (errors == e0)
                $display("PASSOU: %s", name);
        end
    endtask

    // Segundo pacote chega com o Controller ocupado: deve ser ignorado
    task automatic run_busy_case;
        integer e0;
        begin
            e0 = errors;
            clear_counters();

            send_packet(16'd60, KEY_A, 16'd10, 80'h1234);   // pacote A
            repeat (6) @(negedge clk);                      // Controller ocupado

            @(negedge clk);                                 // pacote B (ignorado)
            hash_index    = 16'd61;
            flow_key      = KEY_B;
            packet_length = 16'd99;
            timestamp     = 80'h5678;
            hash_valid    = 1'b1;
            @(negedge clk);
            hash_valid    = 1'b0;

            wait_done();
            repeat (10) @(negedge clk);

            check_run("Pacote com Controller ocupado e ignorado", RESULT_MISS, 5, 13);
            check_entry(16'd60, KEY_A, 32'd1, 32'd10, 80'h1234, 80'h1234);
            check_word({16'd61, 4'd0}, 32'd0, "entrada do pacote B intacta");

            if (errors == e0)
                $display("PASSOU: Pacote com Controller ocupado e ignorado");
        end
    endtask

    // ---------------- Cenarios ----------------
    localparam logic [79:0] TS1 = 80'h0000_0000_0000_0000_1234;
    localparam logic [79:0] TS2 = 80'h0000_0000_0000_0000_5678;

    initial begin
        hash_index    = '0;
        flow_key      = '0;
        packet_length = '0;
        timestamp     = '0;
        hash_valid    = 1'b0;

        repeat (4) @(negedge clk);
        rst = 1'b0;
        repeat (2) @(negedge clk);

        // 1) MISS: entrada vazia (5 leituras, 13 escritas)
        run_case("MISS idx 10", 16'd10, KEY_A, 16'd100, TS1, RESULT_MISS, 5, 13);
        check_entry(16'd10, KEY_A, 32'd1, 32'd100, TS1, TS1);

        // 2) HIT: mesma chave (7 leituras, 5 escritas)
        run_case("HIT idx 10", 16'd10, KEY_A, 16'd50, TS2, RESULT_HIT, 7, 5);
        check_entry(16'd10, KEY_A, 32'd2, 32'd150, TS1, TS2);

        // 3) COLLISION: chave totalmente diferente (5 leituras, 0 escritas)
        run_case("COLLISION chave diferente", 16'd10, KEY_B, 16'd77, 80'h9999,
                 RESULT_COLLISION, 5, 0);
        check_entry(16'd10, KEY_A, 32'd2, 32'd150, TS1, TS2);

        // 4) COLLISION: difere so no bit 0
        run_case("COLLISION bit 0", 16'd10, KEY_A ^ 104'h1, 16'd10, 80'h1,
                 RESULT_COLLISION, 5, 0);

        // 5) COLLISION: difere so no bit 103 (W4[7])
        run_case("COLLISION bit 103", 16'd10, KEY_A ^ (104'h1 << 103), 16'd10, 80'h1,
                 RESULT_COLLISION, 5, 0);
        check_entry(16'd10, KEY_A, 32'd2, 32'd150, TS1, TS2);

        // 6) HIT com lixo em W0[31:1] e W4[31:8]: deve continuar HIT
        preload(16'd30, 32'hFFFFFFFF, KEY_A, 24'hABCDEF);
        poke({16'd30, 4'd5}, 32'd7);
        poke({16'd30, 4'd6}, 32'd700);
        poke({16'd30, 4'd7}, 32'h1111);
        run_case("HIT com bits reservados sujos", 16'd30, KEY_A, 16'd20, TS2,
                 RESULT_HIT, 7, 5);
        check_word({16'd30, 4'd0},  32'hFFFFFFFF, "HIT nao reescreve W0");
        check_word({16'd30, 4'd5},  32'd8,        "HIT W5");
        check_word({16'd30, 4'd6},  32'd720,      "HIT W6");
        check_word({16'd30, 4'd7},  32'h1111,     "HIT preserva first_ts");
        check_word({16'd30, 4'd10}, 32'h5678,     "HIT last_ts");

        // 7) valid usa so o bit 0: W0 = FFFFFFFE -> MISS
        preload(16'd40, 32'hFFFFFFFE, 104'hDEADBEEF, 24'hFFFFFF);
        run_case("MISS com W0 = FFFFFFFE", 16'd40, KEY_A, 16'd64, TS1,
                 RESULT_MISS, 5, 13);
        check_entry(16'd40, KEY_A, 32'd1, 32'd64, TS1, TS1);

        // 8) Limites do hash_index
        run_case("MISS idx 0",     16'h0000, KEY_A, 16'd10, TS1, RESULT_MISS, 5, 13);
        check_entry(16'h0000, KEY_A, 32'd1, 32'd10, TS1, TS1);
        run_case("MISS idx 65535", 16'hFFFF, KEY_A, 16'd11, TS1, RESULT_MISS, 5, 13);
        check_entry(16'hFFFF, KEY_A, 32'd1, 32'd11, TS1, TS1);

        // 9) Pacotes em sequencia no mesmo fluxo
        run_case("Sequencia: MISS", 16'd20, KEY_A, 16'd10, TS1, RESULT_MISS, 5, 13);
        run_case("Sequencia: HIT 1", 16'd20, KEY_A, 16'd10, TS2, RESULT_HIT, 7, 5);
        run_case("Sequencia: HIT 2", 16'd20, KEY_A, 16'd10, 80'h9ABC, RESULT_HIT, 7, 5);
        check_entry(16'd20, KEY_A, 32'd3, 32'd30, TS1, 80'h9ABC);

        // 10) hash_valid mantido em 1 por 80 ciclos: uma unica operacao
        run_held_case("hash_valid mantido em nivel alto", 16'd50, KEY_A, 16'd33, TS1,
                      RESULT_MISS, 5, 13, 80);
        check_entry(16'd50, KEY_A, 32'd1, 32'd33, TS1, TS1);

        // 11) Nova captura aceita depois que valid voltou a zero
        run_case("Nova captura apos valid em baixo", 16'd50, KEY_A, 16'd7, TS2,
                 RESULT_HIT, 7, 5);
        check_entry(16'd50, KEY_A, 32'd2, 32'd40, TS1, TS2);

        // 12) Pacote que chega com o Controller ocupado e ignorado
        run_busy_case();

        repeat (3) @(negedge clk);

        if (errors == 0)
            $display("TODOS OS TESTES PASSARAM!");
        else
            $display("TESTES FINALIZADOS COM %0d ERRO(S).", errors);

        $finish;
    end

    initial begin
        #4000000;
        $fatal(1, "TIMEOUT global");
    end

endmodule