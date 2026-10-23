`timescale 1ns/1ps

// Teste UNITARIO do Controller.
// A Flow Table e substituida por um modelo simples dentro do testbench
// (memoria de 4096 palavras = entradas 0..255, latencia de 1 ciclo).
// Se este teste passa e o de integracao falha, o problema esta na
// integracao (Flow Table real); se este falha, o problema e do Controller.
module tb_controller_unit;

    localparam logic [1:0] RESULT_MISS      = 2'b01;
    localparam logic [1:0] RESULT_COLLISION = 2'b11;

    localparam logic [103:0] KEY_A = 104'h123456789ABCDEF123456789AB;
    localparam logic [103:0] KEY_B = 104'h00000000000000000000000001;
    localparam logic [79:0]  TS1   = 80'h0000_0000_0000_0000_1234;

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
    logic         fin_valid;
    logic         fin_done;
    logic [1:0]   lookup_result;
    logic         lookup_done;
    logic [31:0]  collision_count;

    integer read_count    = 0;
    integer write_count   = 0;
    integer start_count   = 0;
    integer done_count    = 0;
    integer errors        = 0;
    integer coll_expected = 0;

    logic [19:0] rd_log  [0:31];
    logic [19:0] wr_log  [0:31];
    logic [31:0] wr_dlog [0:31];

    logic [31:0] mem [0:4095];

    assign fin_done = 1'b0;

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
        .lookup_result(lookup_result), .lookup_done(lookup_done),
        .collision_count(collision_count)
    );

    // ---------------- Modelo simples da Flow Table ----------------
    integer k;
    initial begin
        for (k = 0; k < 4096; k = k + 1)
            mem[k] = 32'b0;
    end

    always @(posedge clk) begin
        if (rst) begin
            rd_valid <= 1'b0;
            wr_done  <= 1'b0;
            rd_data  <= 32'b0;
        end else begin
            rd_valid <= rd_en;
            wr_done  <= wr_en;
            if (rd_en) rd_data <= mem[rd_addr[11:0]];
            if (wr_en) mem[wr_addr[11:0]] <= wr_data;
        end
    end

    // ---------------- Monitores ----------------
    always @(posedge clk) begin
        if (!rst) begin
            if (rd_en) begin
                if (read_count < 32) rd_log[read_count] <= rd_addr;
                read_count <= read_count + 1;
            end
            if (wr_en) begin
                if (write_count < 32) begin
                    wr_log[write_count]  <= wr_addr;
                    wr_dlog[write_count] <= wr_data;
                end
                write_count <= write_count + 1;
            end
            if (dut.start)   start_count <= start_count + 1;
            if (lookup_done) done_count  <= done_count + 1;
        end
    end

    // ---------------- Valores esperados ----------------
    // Palavra W0..W12 de um registro novo (MISS)
    function automatic logic [31:0] exp_word(
        input integer       w,
        input logic [103:0] key,
        input logic [15:0]  len,
        input logic [79:0]  ts
    );
        begin
            case (w)
                0:  exp_word = 32'd1;
                1:  exp_word = key[31:0];
                2:  exp_word = key[63:32];
                3:  exp_word = key[95:64];
                4:  exp_word = {24'b0, key[103:96]};
                5:  exp_word = 32'd1;
                6:  exp_word = {16'b0, len};
                7:  exp_word = ts[31:0];
                8:  exp_word = ts[63:32];
                9:  exp_word = {16'b0, ts[79:64]};
                10: exp_word = ts[31:0];
                11: exp_word = ts[63:32];
                12: exp_word = {16'b0, ts[79:64]};
                default: exp_word = 32'b0;
            endcase
        end
    endfunction

    // flow_entry esperado apos um MISS: W1..W12 (W1 em [31:0])
    function automatic logic [383:0] exp_entry(
        input logic [103:0] key,
        input logic [15:0]  len,
        input logic [79:0]  ts
    );
        integer w;
        begin
            exp_entry = '0;
            for (w = 1; w <= 12; w = w + 1)
                exp_entry[(w-1)*32 +: 32] = exp_word(w, key, len, ts);
        end
    endfunction

    // ---------------- Tasks ----------------
    task automatic fail(input string msg);
        begin
            $error("%s", msg);
            errors = errors + 1;
        end
    endtask

    task automatic clear_counters;
        begin
            read_count  = 0;
            write_count = 0;
            start_count = 0;
            done_count  = 0;
        end
    endtask

    // Pacote com hash_valid de 1 ciclo; embaralha as entradas em seguida
    task automatic send_packet(
        input logic [15:0]  idx,
        input logic [103:0] key,
        input logic [15:0]  len,
        input logic [79:0]  ts
    );
        begin
            @(negedge clk);
            hash_index    = idx;
            flow_key      = key;
            packet_length = len;
            timestamp     = ts;
            hash_valid    = 1'b1;

            @(negedge clk);
            hash_valid    = 1'b0;
            hash_index    = $urandom;
            flow_key      = {$urandom, $urandom, $urandom, $urandom};
            packet_length = $urandom;
            timestamp     = {$urandom, $urandom, $urandom};
        end
    endtask

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

    // Resultado, contagens, enderecos e contador de colisoes
    task automatic check_ops(
        input string       name,
        input logic [15:0] idx,
        input logic [1:0]  exp_res
    );
        integer i;
        integer exp_wr;
        begin
            exp_wr = (exp_res == RESULT_MISS) ? 13 : 0;
            if (exp_res == RESULT_COLLISION)
                coll_expected = coll_expected + 1;

            if (lookup_result !== exp_res)
                fail($sformatf("%s: resultado=%b esperado=%b", name, lookup_result, exp_res));
            if (read_count != 5)
                fail($sformatf("%s: leituras=%0d esperado=5", name, read_count));
            if (write_count != exp_wr)
                fail($sformatf("%s: escritas=%0d esperado=%0d", name, write_count, exp_wr));
            if (start_count != 1)
                fail($sformatf("%s: pulsos de start=%0d esperado=1", name, start_count));
            if (done_count != 1)
                fail($sformatf("%s: pulsos de lookup_done=%0d esperado=1", name, done_count));
            if (collision_count !== coll_expected)
                fail($sformatf("%s: collision_count=%0d esperado=%0d",
                               name, collision_count, coll_expected));

            // Leituras em ordem: W0..W4 da entrada
            for (i = 0; i < 5; i = i + 1)
                if (rd_log[i] !== {idx, i[3:0]})
                    fail($sformatf("%s: leitura %0d no endereco %0d", name, i, rd_log[i]));

            // Escritas em ordem: W0..W12 (somente MISS)
            for (i = 0; i < exp_wr; i = i + 1)
                if (wr_log[i] !== {idx, i[3:0]})
                    fail($sformatf("%s: escrita %0d no endereco %0d", name, i, wr_log[i]));
        end
    endtask

    // Memoria da entrada igual ao registro esperado (W0..W12)
    task automatic check_mem(
        input string        name,
        input logic [15:0]  idx,
        input logic [103:0] key,
        input logic [15:0]  len,
        input logic [79:0]  ts
    );
        integer w;
        begin
            for (w = 0; w <= 12; w = w + 1)
                if (mem[idx*16 + w] !== exp_word(w, key, len, ts))
                    fail($sformatf("%s: W%0d esperado=%h obtido=%h", name, w,
                                   exp_word(w, key, len, ts), mem[idx*16 + w]));
        end
    endtask

    // MISS: flow_entry deve conter o registro novo (W1..W12)
    task automatic check_flow_entry_miss(
        input string        name,
        input logic [103:0] key,
        input logic [15:0]  len,
        input logic [79:0]  ts
    );
        begin
            if (flow_entry !== exp_entry(key, len, ts))
                fail($sformatf("%s: flow_entry incorreto", name));
        end
    endtask

    // COLLISION: flow_entry tem so W1..W4 da entrada existente, resto zerado
    task automatic check_flow_entry_collision(
        input string        name,
        input logic [103:0] stored_key
    );
        logic [127:0] w1_w4;
        begin
            w1_w4 = {exp_word(4, stored_key, 16'd0, 80'd0),
                     exp_word(3, stored_key, 16'd0, 80'd0),
                     exp_word(2, stored_key, 16'd0, 80'd0),
                     exp_word(1, stored_key, 16'd0, 80'd0)};
            if (flow_entry[127:0] !== w1_w4)
                fail($sformatf("%s: flow_entry[127:0] diferente da chave armazenada", name));
            if (flow_entry[383:128] !== 256'b0)
                fail($sformatf("%s: flow_entry[383:128] deveria ser zero", name));
        end
    endtask

    // Cenario padrao: hash_valid de 1 ciclo
    task automatic run_case(
        input string        name,
        input logic [15:0]  idx,
        input logic [103:0] key,
        input logic [15:0]  len,
        input logic [79:0]  ts,
        input logic [1:0]   exp_res
    );
        integer e0;
        begin
            e0 = errors;
            clear_counters();
            send_packet(idx, key, len, ts);
            wait_done();
            check_ops(name, idx, exp_res);
            if (errors == e0)
                $display("PASSOU: %s", name);
        end
    endtask

    // hash_valid mantido em 1 por 'hold' ciclos: uma unica operacao
    task automatic run_held_case(
        input string        name,
        input logic [15:0]  idx,
        input logic [103:0] key,
        input logic [15:0]  len,
        input logic [79:0]  ts,
        input integer       hold
    );
        integer e0;
        begin
            e0 = errors;
            clear_counters();

            @(negedge clk);
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

            repeat (hold) @(negedge clk);
            hash_valid = 1'b0;
            repeat (10) @(negedge clk);

            check_ops(name, idx, RESULT_MISS);
            check_mem(name, idx, key, len, ts);

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

            send_packet(16'd60, KEY_A, 16'd10, TS1);
            repeat (6) @(negedge clk);

            @(negedge clk);
            hash_index    = 16'd61;
            flow_key      = KEY_B;
            packet_length = 16'd99;
            timestamp     = 80'h5678;
            hash_valid    = 1'b1;
            @(negedge clk);
            hash_valid    = 1'b0;

            wait_done();
            repeat (10) @(negedge clk);

            check_ops("Pacote com Controller ocupado e ignorado", 16'd60, RESULT_MISS);
            check_mem("Pacote A gravado", 16'd60, KEY_A, 16'd10, TS1);
            if (mem[16'd61*16] !== 32'd0)
                fail("entrada do pacote B deveria estar intacta");

            if (errors == e0)
                $display("PASSOU: Pacote com Controller ocupado e ignorado");
        end
    endtask

    // ---------------- Cenarios ----------------
    initial begin
        hash_index    = '0;
        flow_key      = '0;
        packet_length = '0;
        timestamp     = '0;
        hash_valid    = 1'b0;

        repeat (4) @(negedge clk);
        rst = 1'b0;
        repeat (2) @(negedge clk);

        // 1) MISS: entrada vazia
        run_case("MISS idx 5", 16'd5, KEY_A, 16'd100, TS1, RESULT_MISS);
        check_mem("MISS idx 5 (memoria)", 16'd5, KEY_A, 16'd100, TS1);
        check_flow_entry_miss("MISS idx 5", KEY_A, 16'd100, TS1);

        // 2) COLLISION: chave totalmente diferente, entrada preservada
        run_case("COLLISION chave diferente", 16'd5, KEY_B, 16'd77, 80'h9999, RESULT_COLLISION);
        check_mem("COLLISION preserva entrada", 16'd5, KEY_A, 16'd100, TS1);
        check_flow_entry_collision("COLLISION chave diferente", KEY_A);

        // 3) COLLISION: difere so no bit 103 (W4[7])
        run_case("COLLISION bit 103", 16'd5, KEY_A ^ (104'h1 << 103), 16'd10, 80'h1,
                 RESULT_COLLISION);
        check_mem("COLLISION bit 103 preserva entrada", 16'd5, KEY_A, 16'd100, TS1);

        // 4) COLLISION: difere so no bit 0
        run_case("COLLISION bit 0", 16'd5, KEY_A ^ 104'h1, 16'd10, 80'h1, RESULT_COLLISION);
        check_mem("COLLISION bit 0 preserva entrada", 16'd5, KEY_A, 16'd100, TS1);

        // 5) MISS nao altera o contador de colisoes; valid usa so o bit 0
        mem[16'd200*16 + 0] = 32'hFFFFFFFE;      // valid = 0, bits reservados sujos
        mem[16'd200*16 + 4] = 32'hFFFFFF00;      // lixo em W4[31:8]
        run_case("MISS com W0 = FFFFFFFE", 16'd200, KEY_A, 16'd64, TS1, RESULT_MISS);
        check_mem("MISS idx 200 (memoria)", 16'd200, KEY_A, 16'd64, TS1);
        check_flow_entry_miss("MISS idx 200", KEY_A, 16'd64, TS1);

        // 6) Limites do hash_index do modelo
        run_case("MISS idx 0",   16'd0,   KEY_A, 16'd10, TS1, RESULT_MISS);
        check_mem("MISS idx 0 (memoria)", 16'd0, KEY_A, 16'd10, TS1);
        run_case("MISS idx 255", 16'd255, KEY_A, 16'd11, TS1, RESULT_MISS);
        check_mem("MISS idx 255 (memoria)", 16'd255, KEY_A, 16'd11, TS1);

        // 7) Recepcao: hash_valid mantido em 1 por 80 ciclos
        run_held_case("hash_valid mantido em nivel alto", 16'd50, KEY_A, 16'd33, TS1, 80);

        // 8) Recepcao: pacote com o Controller ocupado e ignorado
        run_busy_case();

        repeat (3) @(negedge clk);

        if (collision_count !== 3)
            fail($sformatf("collision_count final=%0d esperado=3", collision_count));

        if (errors == 0)
            $display("TODOS OS TESTES UNITARIOS PASSARAM!");
        else
            $display("TESTES UNITARIOS FINALIZADOS COM %0d ERRO(S).", errors);

        $finish;
    end

    initial begin
        #4000000;
        $fatal(1, "TIMEOUT global");
    end

endmodule