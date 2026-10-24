`timescale 1ns/1ps

// =====================================================================
// TESTE UNITARIO DO CONTROLLER
//
// A Flow Table e substituida por um modelo simples dentro do testbench
// (memoria de 16384 palavras = entradas 0..1023), com latencia
// configuravel de leitura (RD_LAT) e de escrita (WR_LAT).
//
// O modulo unit_env executa toda a bateria para UMA configuracao de
// latencia. O topo (tb_controller_unit) instancia 4 configuracoes.
//
// Se este teste passa e o de integracao falha, o problema esta na
// integracao (Flow Table real); se este falha, o problema e do Controller.
//
// Bateria:
//   1) Cenarios dirigidos: MISS, HIT, COLLISION (chave toda diferente,
//      bit 0, bit 103), bits reservados sujos, W0 = FFFFFFFE, limites do
//      hash_index, hash_valid mantido em nivel alto.
//   2) Varredura: segundo pacote chegando em TODOS os instantes da
//      operacao do primeiro (aceito so em IDLE, ignorado se ocupado).
//   3) Reset no meio do lookup e no meio das escritas.
//   4) Regressao aleatoria com modelo de referencia (scoreboard).
//   5) Checagens de protocolo em todos os ciclos.
//   6) Varredura final de toda a memoria contra o modelo de referencia.
// =====================================================================
module unit_env #(
    parameter int RD_LAT   = 1,
    parameter int WR_LAT   = 1,
    parameter int N_RANDOM = 300,
    parameter bit FULL_RANGE = 1'b0,
    parameter bit QUIET    = 1'b0
) (
    output logic   done,
    output integer errors
);

    localparam int ENTRIES = FULL_RANGE ? 65536 : 1024;
    localparam int WORDS = ENTRIES * 16;
    localparam logic [1:0] RESULT_NONE      = 2'b00;
    localparam logic [1:0] RESULT_MISS      = 2'b01;
    localparam logic [1:0] RESULT_HIT       = 2'b10;
    localparam logic [1:0] RESULT_COLLISION = 2'b11;

    localparam logic [103:0] KEY_A = 104'h123456789ABCDEF123456789AB;
    localparam logic [103:0] KEY_B = 104'h00000000000000000000000001;
    localparam logic [79:0]  TS1   = 80'h0000_0000_0000_0000_1234;
    localparam logic [79:0]  TS2   = 80'h0000_0000_0000_0000_5678;

    // Duracao aproximada de uma operacao MISS (para a varredura)
    localparam int SW = 5*(1+RD_LAT) + 13*(1+WR_LAT) + 10;

    string tag;
    initial tag = $sformatf("[RD=%0d WR=%0d]", RD_LAT, WR_LAT);

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
    logic         scan_done;

    integer read_count  = 0;
    integer write_count = 0;
    integer start_count = 0;
    integer done_count  = 0;
    integer verbose     = 1;
    integer cov_miss    = 0;
    integer cov_hit     = 0;
    integer cov_coll    = 0;

    logic [19:0] rd_log  [0:31];
    logic [19:0] wr_log  [0:31];
    logic [31:0] wr_dlog [0:31];

    logic [31:0] mem [0:WORDS-1];

    // Modelo de referencia (scoreboard)
    logic         ref_valid [0:ENTRIES-1];
    logic         ref_skip  [0:ENTRIES-1];
    logic [103:0] ref_key   [0:ENTRIES-1];
    logic [31:0]  ref_pkts  [0:ENTRIES-1];
    logic [31:0]  ref_bytes [0:ENTRIES-1];
    logic [79:0]  ref_first [0:ENTRIES-1];
    logic [79:0]  ref_last  [0:ENTRIES-1];
    integer       ref_coll = 0;

    logic [103:0] pool [0:3];

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
        .collision_count(collision_count),
        .fin_start(1'b0), .scan_done(scan_done)
    );

    // ---------------- Modelo da Flow Table (latencia configuravel) ----------------
    logic        rd_v_sr [1:RD_LAT];
    logic [31:0] rd_d_sr [1:RD_LAT];
    logic        wr_v_sr [1:WR_LAT];
    integer      i_m;

    always @(posedge clk) begin
        if (rst) begin
            for (i_m = 1; i_m <= RD_LAT; i_m = i_m + 1) begin
                rd_v_sr[i_m] <= 1'b0;
                rd_d_sr[i_m] <= 32'b0;
            end
            for (i_m = 1; i_m <= WR_LAT; i_m = i_m + 1)
                wr_v_sr[i_m] <= 1'b0;
        end else begin
            rd_v_sr[1] <= rd_en;
            rd_d_sr[1] <= rd_en ? mem[rd_addr] : 32'b0;
            for (i_m = 2; i_m <= RD_LAT; i_m = i_m + 1) begin
                rd_v_sr[i_m] <= rd_v_sr[i_m-1];
                rd_d_sr[i_m] <= rd_d_sr[i_m-1];
            end
            wr_v_sr[1] <= wr_en;
            for (i_m = 2; i_m <= WR_LAT; i_m = i_m + 1)
                wr_v_sr[i_m] <= wr_v_sr[i_m-1];
            if (wr_en) mem[wr_addr] <= wr_data;
        end
    end

    assign rd_valid = rd_v_sr[RD_LAT];
    assign rd_data  = rd_d_sr[RD_LAT];
    assign wr_done  = wr_v_sr[WR_LAT];

    // ---------------- Utilitarios ----------------
    task automatic fail(input string msg);
        begin
            $error("%s %s", tag, msg);
            errors = errors + 1;
        end
    endtask

    task automatic pass(input string name);
        begin
            if (verbose != 0 && !QUIET)
                $display("%s PASSOU: %s", tag, name);
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

    // ---------------- Monitores e checagens de protocolo ----------------
    logic rd_en_q = 1'b0, wr_en_q = 1'b0, done_q = 1'b0;

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

            rd_en_q <= rd_en;
            wr_en_q <= wr_en;
            done_q  <= lookup_done;

            // Protocolo
            if ((^{rd_en, wr_en, lookup_done, lookup_result, collision_count, fin_valid}) === 1'bx)
                fail("saida de controle com valor desconhecido (X)");
            if (rd_en && wr_en)
                fail("rd_en e wr_en ativos ao mesmo tempo");
            if (rd_en && rd_en_q)
                fail("rd_en ativo por mais de 1 ciclo");
            if (wr_en && wr_en_q)
                fail("wr_en ativo por mais de 1 ciclo");
            if (lookup_done && done_q)
                fail("lookup_done ativo por mais de 1 ciclo");
            if (lookup_done && (rd_en || wr_en))
                fail("acesso a memoria no ciclo de lookup_done");
            if (wr_en && lookup_result == RESULT_COLLISION)
                fail("escrita durante uma COLLISION");
            if (wr_en && lookup_result == RESULT_NONE)
                fail("escrita antes da classificacao");
            if (fin_valid)
                fail("fin_valid deveria ser 0 nesta etapa");
            if (rd_en && !FULL_RANGE && rd_addr[19:14] !== 6'b0)
                fail("rd_addr fora da faixa do modelo");
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

    // W1..W4 como estao na memoria agora (o que o lookup vai ler)
    function automatic logic [127:0] snap_w1w4(input logic [15:0] idx);
        begin
            snap_w1w4 = {mem[idx*16 + 4], mem[idx*16 + 3],
                         mem[idx*16 + 2], mem[idx*16 + 1]};
        end
    endfunction

    // ---------------- Envio de pacotes ----------------
    task automatic scramble;
        begin
            hash_index    = $urandom;
            flow_key      = {$urandom, $urandom, $urandom, $urandom};
            packet_length = $urandom;
            timestamp     = {$urandom, $urandom, $urandom};
        end
    endtask

    // hash_valid de 1 ciclo; embaralha as entradas em seguida
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
            scramble();
        end
    endtask

    // hash_valid mantido em 1 por 'hold' ciclos
    task automatic hold_packet(
        input logic [15:0]  idx,
        input logic [103:0] key,
        input logic [15:0]  len,
        input logic [79:0]  ts,
        input integer       hold
    );
        begin
            @(negedge clk);
            hash_index    = idx;
            flow_key      = key;
            packet_length = len;
            timestamp     = ts;
            hash_valid    = 1'b1;
            @(negedge clk);
            scramble();
            repeat (hold) @(negedge clk);
            hash_valid    = 1'b0;
        end
    endtask

    // Espera ate 'target' pulsos de lookup_done (contagem do monitor)
    task automatic wait_done(input integer target);
        integer t;
        begin
            t = 0;
            while (done_count < target && t < 5000) begin
                @(negedge clk);
                t = t + 1;
            end
            if (t >= 5000)
                $fatal(1, "%s TIMEOUT esperando lookup_done", tag);
            repeat (2) @(negedge clk);
        end
    endtask

    // ---------------- Modelo de referencia ----------------
    task automatic update_ref(
        input logic [15:0]  idx,
        input logic [1:0]   res,
        input logic [103:0] key,
        input logic [15:0]  len,
        input logic [79:0]  ts
    );
        begin
            case (res)
                RESULT_MISS: begin
                    ref_valid[idx] = 1'b1;
                    ref_key[idx]   = key;
                    ref_pkts[idx]  = 32'd1;
                    ref_bytes[idx] = {16'b0, len};
                    ref_first[idx] = ts;
                    ref_last[idx]  = ts;
                end
                RESULT_HIT: begin
                    ref_pkts[idx]  = ref_pkts[idx] + 32'd1;
                    ref_bytes[idx] = ref_bytes[idx] + {16'b0, len};
                    ref_last[idx]  = ts;
                end
                default: ;
            endcase
        end
    endtask

    // Memoria da entrada igual ao modelo (W0 so bit 0, W4 so [7:0])
    task automatic check_mem_entry(input string name, input logic [15:0] idx);
        logic [31:0] b;
        begin
            b = idx * 16;
            if (ref_valid[idx]) begin
                if (mem[b+0][0]   !== 1'b1)                 fail($sformatf("%s: idx %0d W0.valid", name, idx));
                if (mem[b+1]      !== ref_key[idx][31:0])   fail($sformatf("%s: idx %0d W1", name, idx));
                if (mem[b+2]      !== ref_key[idx][63:32])  fail($sformatf("%s: idx %0d W2", name, idx));
                if (mem[b+3]      !== ref_key[idx][95:64])  fail($sformatf("%s: idx %0d W3", name, idx));
                if (mem[b+4][7:0] !== ref_key[idx][103:96]) fail($sformatf("%s: idx %0d W4", name, idx));
                if (mem[b+5]      !== ref_pkts[idx])        fail($sformatf("%s: idx %0d W5 pkts esperado=%0d obtido=%0d", name, idx, ref_pkts[idx], mem[b+5]));
                if (mem[b+6]      !== ref_bytes[idx])       fail($sformatf("%s: idx %0d W6 bytes esperado=%0d obtido=%0d", name, idx, ref_bytes[idx], mem[b+6]));
                if (mem[b+7]      !== ref_first[idx][31:0]) fail($sformatf("%s: idx %0d W7", name, idx));
                if (mem[b+8]      !== ref_first[idx][63:32])fail($sformatf("%s: idx %0d W8", name, idx));
                if (mem[b+9]      !== {16'b0, ref_first[idx][79:64]}) fail($sformatf("%s: idx %0d W9", name, idx));
                if (mem[b+10]     !== ref_last[idx][31:0])  fail($sformatf("%s: idx %0d W10", name, idx));
                if (mem[b+11]     !== ref_last[idx][63:32]) fail($sformatf("%s: idx %0d W11", name, idx));
                if (mem[b+12]     !== {16'b0, ref_last[idx][79:64]}) fail($sformatf("%s: idx %0d W12", name, idx));
            end else begin
                if (mem[b+0][0] !== 1'b0)
                    fail($sformatf("%s: idx %0d deveria estar invalido", name, idx));
            end
        end
    endtask

    // Verifica uma operacao concluida contra o modelo de referencia
    task automatic verify(
        input string        name,
        input logic [15:0]  idx,
        input logic [1:0]   exp_res,
        input logic [127:0] snap,
        input logic [103:0] key,
        input logic [15:0]  len,
        input logic [79:0]  ts
    );
        integer i, exp_rd, exp_wr, w;
        logic [31:0]  new_pkts, new_bytes, exp_d;
        logic [383:0] exp_fe;
        begin
            exp_rd    = (exp_res == RESULT_HIT) ? 7 : 5;
            exp_wr    = (exp_res == RESULT_MISS) ? 13 : (exp_res == RESULT_HIT) ? 5 : 0;
            new_pkts  = ref_pkts[idx] + 32'd1;
            new_bytes = ref_bytes[idx] + {16'b0, len};
            if (exp_res == RESULT_COLLISION)
                ref_coll = ref_coll + 1;

            if (lookup_result !== exp_res)
                fail($sformatf("%s: resultado=%b esperado=%b", name, lookup_result, exp_res));
            if (read_count != exp_rd)
                fail($sformatf("%s: leituras=%0d esperado=%0d", name, read_count, exp_rd));
            if (write_count != exp_wr)
                fail($sformatf("%s: escritas=%0d esperado=%0d", name, write_count, exp_wr));
            if (start_count != 1)
                fail($sformatf("%s: pulsos de start=%0d esperado=1", name, start_count));
            if (done_count != 1)
                fail($sformatf("%s: pulsos de lookup_done=%0d esperado=1", name, done_count));
            if (collision_count !== ref_coll)
                fail($sformatf("%s: collision_count=%0d esperado=%0d", name, collision_count, ref_coll));

            // Leituras em ordem
            for (i = 0; i < exp_rd; i = i + 1)
                if (rd_log[i] !== {idx, i[3:0]})
                    fail($sformatf("%s: leitura %0d no endereco %0d", name, i, rd_log[i]));

            // Escritas em ordem e com o dado correto
            for (i = 0; i < exp_wr; i = i + 1) begin
                if (exp_res == RESULT_MISS) begin
                    w     = i;
                    exp_d = exp_word(i, key, len, ts);
                end else begin
                    w = (i < 2) ? (5 + i) : (8 + i);   // 5, 6, 10, 11, 12
                    case (w)
                        5:  exp_d = new_pkts;
                        6:  exp_d = new_bytes;
                        10: exp_d = ts[31:0];
                        11: exp_d = ts[63:32];
                        default: exp_d = {16'b0, ts[79:64]};
                    endcase
                end
                if (wr_log[i] !== {idx, w[3:0]})
                    fail($sformatf("%s: escrita %0d no endereco %0d", name, i, wr_log[i]));
                if (wr_dlog[i] !== exp_d)
                    fail($sformatf("%s: escrita W%0d esperado=%h obtido=%h", name, w, exp_d, wr_dlog[i]));
            end

            // flow_entry (W1..W12)
            case (exp_res)
                RESULT_MISS: exp_fe = exp_entry(key, len, ts);
                RESULT_HIT:  exp_fe = {{16'b0, ts[79:64]}, ts[63:32], ts[31:0],
                                       96'b0, new_bytes, new_pkts, snap};
                default:     exp_fe = {256'b0, snap};
            endcase
            if (flow_entry !== exp_fe)
                fail($sformatf("%s: flow_entry incorreto", name));
        end
    endtask

    // Envia um pacote (hold = 0: 1 ciclo; hold > 0: valid mantido) e confere tudo
    task automatic do_packet(
        input string        name,
        input logic [15:0]  idx,
        input logic [103:0] key,
        input logic [15:0]  len,
        input logic [79:0]  ts,
        input integer       hold
    );
        integer e0;
        logic [1:0]   exp_res;
        logic [127:0] snap;
        begin
            e0   = errors;
            snap = snap_w1w4(idx);
            if (!ref_valid[idx])            exp_res = RESULT_MISS;
            else if (ref_key[idx] === key)  exp_res = RESULT_HIT;
            else                            exp_res = RESULT_COLLISION;

            case (exp_res)
                RESULT_MISS: cov_miss = cov_miss + 1;
                RESULT_HIT:  cov_hit  = cov_hit  + 1;
                default:     cov_coll = cov_coll + 1;
            endcase

            clear_counters();
            if (hold == 0) begin
                send_packet(idx, key, len, ts);
                wait_done(1);
            end else begin
                hold_packet(idx, key, len, ts, hold);
                wait_done(1);
                repeat (10) @(negedge clk);
            end

            verify(name, idx, exp_res, snap, key, len, ts);
            update_ref(idx, exp_res, key, len, ts);
            check_mem_entry(name, idx);

            if (errors == e0) pass(name);
        end
    endtask

    // Segundo pacote chega 'off' ciclos depois do primeiro (1 ciclo de valid)
    task automatic sweep_one(input integer off);
        integer e0, target;
        logic [15:0] a, b;
        logic        acc;
        begin
            e0 = errors;
            a  = 300 + off;
            b  = 500 + off;
            clear_counters();

            send_packet(a, KEY_A, 16'd10, TS1);
            repeat (off) @(negedge clk);

            hash_index    = b;
            flow_key      = KEY_B;
            packet_length = 16'd99;
            timestamp     = 80'h5678;
            acc           = (dut.state == dut.IDLE);   // aceito somente em IDLE
            hash_valid    = 1'b1;
            @(negedge clk);
            hash_valid    = 1'b0;
            scramble();

            target = acc ? 2 : 1;
            wait_done(target);
            repeat (10) @(negedge clk);

            if (start_count != target)
                fail($sformatf("varredura off=%0d: start=%0d esperado=%0d", off, start_count, target));
            if (done_count != target)
                fail($sformatf("varredura off=%0d: done=%0d esperado=%0d", off, done_count, target));

            update_ref(a, RESULT_MISS, KEY_A, 16'd10, TS1);
            check_mem_entry("varredura A", a);
            if (acc) update_ref(b, RESULT_MISS, KEY_B, 16'd99, 80'h5678);
            check_mem_entry("varredura B", b);
            if (collision_count !== ref_coll)
                fail($sformatf("varredura off=%0d: collision_count=%0d", off, collision_count));

            if (errors != e0)
                fail($sformatf("varredura falhou no deslocamento %0d", off));
        end
    endtask

    // Reset no meio da operacao
    task automatic reset_mid(
        input string       name,
        input logic [15:0] idx,
        input integer      delay,
        input bit          taint
    );
        integer e0, rd0, wr0;
        begin
            e0 = errors;
            clear_counters();

            send_packet(idx, KEY_A, 16'd10, TS1);
            repeat (delay) @(negedge clk);
            rst = 1'b1;
            repeat (2) @(negedge clk);
            rst = 1'b0;

            rd0 = read_count;
            wr0 = write_count;
            repeat (15) @(negedge clk);

            if (dut.state !== dut.IDLE)
                fail($sformatf("%s: Controller nao voltou a IDLE", name));
            if (collision_count !== 32'd0)
                fail($sformatf("%s: collision_count nao foi zerado pelo reset", name));
            if (lookup_result !== RESULT_NONE)
                fail($sformatf("%s: lookup_result nao foi zerado", name));
            if (flow_entry !== 384'b0)
                fail($sformatf("%s: flow_entry nao foi zerado", name));
            if (done_count != 0)
                fail($sformatf("%s: lookup_done indevido apos o reset", name));
            if (read_count != rd0 || write_count != wr0)
                fail($sformatf("%s: acesso a memoria apos o reset", name));

            ref_coll = 0;
            if (taint) ref_skip[idx] = 1'b1;

            if (errors == e0) pass(name);
        end
    endtask

    // ---------------- Sequencia de testes ----------------
    integer n, off, ix;
    logic [15:0]  r_idx, r_len;
    logic [103:0] r_key;
    logic [79:0]  r_ts;
    integer       r_hold;

    initial begin
        done       = 1'b0;
        errors     = 0;
        hash_index = '0;
        flow_key   = '0;
        packet_length = '0;
        timestamp  = '0;
        hash_valid = 1'b0;

        for (ix = 0; ix < WORDS; ix = ix + 1) mem[ix] = 32'b0;
        for (ix = 0; ix < ENTRIES; ix = ix + 1) begin
            ref_valid[ix] = 1'b0;
            ref_skip[ix]  = 1'b0;
            ref_key[ix]   = '0;
            ref_pkts[ix]  = '0;
            ref_bytes[ix] = '0;
            ref_first[ix] = '0;
            ref_last[ix]  = '0;
        end
        pool[0] = KEY_A;
        pool[1] = KEY_B;
        pool[2] = KEY_A ^ 104'h1;
        pool[3] = KEY_A ^ (104'h1 << 103);

        repeat (4) @(negedge clk);
        rst = 1'b0;
        repeat (2) @(negedge clk);

        // ---------- 1) Cenarios dirigidos ----------
        do_packet("MISS idx 5",                    16'd5, KEY_A, 16'd100, TS1, 0);
        do_packet("HIT idx 5",                     16'd5, KEY_A, 16'd50,  TS2, 0);
        do_packet("COLLISION chave diferente",     16'd5, KEY_B, 16'd77,  80'h9999, 0);
        do_packet("COLLISION bit 103",             16'd5, KEY_A ^ (104'h1 << 103), 16'd10, 80'h1, 0);
        do_packet("COLLISION bit 0",               16'd5, KEY_A ^ 104'h1, 16'd10, 80'h1, 0);
        do_packet("HIT apos colisoes",             16'd5, KEY_A, 16'd20,  TS2, 0);

        mem[16'd5*16 + 0] = mem[16'd5*16 + 0] | 32'hFFFFFFFE;   // lixo em W0[31:1]
        mem[16'd5*16 + 4] = mem[16'd5*16 + 4] | 32'hFFFFFF00;   // lixo em W4[31:8]
        do_packet("HIT com bits reservados sujos",       16'd5, KEY_A, 16'd1, TS1, 0);
        do_packet("COLLISION com bits reservados sujos", 16'd5, KEY_B, 16'd1, TS1, 0);

        mem[16'd200*16 + 0] = 32'hFFFFFFFE;                     // valid = 0
        mem[16'd200*16 + 4] = 32'hFFFFFF00;
        do_packet("MISS com W0 = FFFFFFFE",        16'd200,  KEY_A, 16'd64, TS1, 0);

        do_packet("MISS idx 0",                    16'd0,    KEY_A, 16'd10, TS1, 0);
        do_packet("MISS idx 1023",                 16'd1023, KEY_A, 16'd11, TS1, 0);

        do_packet("hash_valid mantido (80 ciclos): MISS", 16'd50, KEY_A, 16'd33, TS1, 80);
        do_packet("hash_valid mantido (30 ciclos): HIT",  16'd50, KEY_A, 16'd7,  TS2, 30);

        // ---------- Limites do campo de entrada e aritmetica ----------
        do_packet("pacote de 0 bytes", 16'd75, KEY_A, 16'd0, 80'h0, 0);
        do_packet("pacote de 65535 bytes", 16'd75, KEY_A, 16'hFFFF, 80'hFFFF_FFFF_FFFF_FFFF_FFFF, 0);
        do_packet("timestamp 80 bits maximo", 16'd75, KEY_A, 16'd1, 80'hFFFF_FFFF_FFFF_FFFF_FFFF, 0);
        do_packet("timestamp 80 bits minimo", 16'd75, KEY_A, 16'd1, 80'h0, 0);

        // Pre-carrega contadores nos limites, mantendo scoreboard coerente.
        // Aritmetica de W5/W6 no RTL e modular em 32 bits.
        mem[16'd76*16 + 0] = 32'd1;
        mem[16'd76*16 + 1] = KEY_A[31:0];
        mem[16'd76*16 + 2] = KEY_A[63:32];
        mem[16'd76*16 + 3] = KEY_A[95:64];
        mem[16'd76*16 + 4] = {24'b0, KEY_A[103:96]};
        mem[16'd76*16 + 5] = 32'hFFFFFFFF;
        mem[16'd76*16 + 6] = 32'hFFFFFFFE;
        for (ix = 7; ix <= 12; ix = ix + 1) mem[16'd76*16 + ix] = 32'b0;
        ref_valid[76] = 1'b1;
        ref_key[76] = KEY_A;
        ref_pkts[76] = 32'hFFFFFFFF;
        ref_bytes[76] = 32'hFFFFFFFE;
        ref_first[76] = 80'b0;
        ref_last[76] = 80'b0;
        do_packet("overflow de packet_count e byte_count", 16'd76, KEY_A, 16'd3, TS1, 0);
        do_packet("incremento apos overflow", 16'd76, KEY_A, 16'hFFFF, TS2, 0);

        // Contador de colisao saturante, conferindo os dois ultimos incrementos.
        dut.collision_count = 32'hFFFFFFFE;
        ref_coll = -2; // mesmo padrao binario FFFFFFFE
        do_packet("collision_count atinge FFFFFFFF", 16'd5, KEY_B, 16'd1, TS1, 0);
        // O scoreboard normalmente soma colisao; a saturacao exige teste separado.
        begin : sat_collision
            integer old_errors;
            old_errors = errors;
            clear_counters();
            send_packet(16'd5, KEY_B, 16'd1, TS1);
            wait_done(1);
            if (lookup_result !== RESULT_COLLISION)
                fail("colisao saturada: resultado nao e COLLISION");
            if (collision_count !== 32'hFFFFFFFF)
                fail("colisao saturada: contador deu volta");
            if (read_count != 5 || write_count != 0 || done_count != 1)
                fail("colisao saturada: handshake de leitura/escrita incorreto");
            if (errors == old_errors) pass("collision_count permanece saturado");
        end
        // Reinicia o contador para permitir o scoreboard regular a seguir.
        dut.collision_count = 32'd0;
        ref_coll = 0;

        if (FULL_RANGE) begin
            do_packet("MISS idx 65535", 16'hFFFF, KEY_A, 16'd65535, TS1, 0);
            do_packet("HIT idx 65535", 16'hFFFF, KEY_A, 16'd1, TS2, 0);
            do_packet("COLLISION idx 65535", 16'hFFFF, KEY_B, 16'd1, TS2, 0);
            do_packet("MISS idx 32768", 16'h8000, KEY_B, 16'd0, 80'h0, 0);
        end

        // ---------- 2) Varredura de chegada do segundo pacote ----------
        for (off = 1; off <= SW; off = off + 1)
            sweep_one(off);
        if (verbose != 0)
            $display("%s PASSOU: varredura de pacote ocupado (%0d deslocamentos)", tag, SW);

        // ---------- 3) Reset no meio da operacao ----------
        reset_mid("Reset durante o lookup",   16'd900, 6,  0);
        reset_mid("Reset durante as escritas", 16'd901, 30, 1);
        do_packet("Recuperacao apos reset: MISS",      16'd902, KEY_A, 16'd10, TS1, 0);
        do_packet("Recuperacao apos reset: COLLISION", 16'd902, KEY_B, 16'd10, TS1, 0);

        // ---------- 4) Regressao aleatoria com modelo de referencia ----------
        verbose = 0;
        for (n = 0; n < N_RANDOM; n = n + 1) begin
            r_idx  = $urandom_range(0, 39);
            // 65% das vezes usa a chave "preferida" do indice (gera HIT);
            // senao sorteia outra (gera COLLISION); indices novos geram MISS
            r_key  = ($urandom_range(0, 99) < 65) ? pool[r_idx % 4]
                                                   : pool[$urandom_range(0, 3)];
            r_len  = $urandom;
            r_ts   = {$urandom, $urandom, $urandom};
            r_hold = ($urandom_range(0, 9) == 0) ? $urandom_range(45, 120) : 0;
            do_packet("aleatorio", r_idx, r_key, r_len, r_ts, r_hold);

            repeat ($urandom_range(0, 4)) @(negedge clk);

            if ($urandom_range(0, 3) == 0) begin      // lixo nos bits reservados
                mem[r_idx*16 + 0] = mem[r_idx*16 + 0] | ($urandom & 32'hFFFFFFFE);
                mem[r_idx*16 + 4] = mem[r_idx*16 + 4] | ($urandom & 32'hFFFFFF00);
            end
        end
        verbose = 1;
        if (errors == 0)
            $display("%s PASSOU: regressao aleatoria (%0d pacotes; total no teste: MISS=%0d HIT=%0d COLLISION=%0d)",
                     tag, N_RANDOM, cov_miss, cov_hit, cov_coll);

        // ---------- 5) Varredura final da memoria ----------
        for (ix = 0; ix < ENTRIES; ix = ix + 1)
            if (!ref_skip[ix])
                check_mem_entry("varredura final", ix);
        if (collision_count !== ref_coll)
            fail($sformatf("collision_count final=%0d esperado=%0d", collision_count, ref_coll));
        if (verbose != 0 && errors == 0)
            $display("%s PASSOU: varredura final da memoria (collision_count = %0d)", tag, collision_count);

        done = 1'b1;
    end

endmodule


// =====================================================================
// TESTE DA VARREDURA / FINALIZACAO DO CONTROLLER  (PROVISORIO)
//
// A Flow Table e um modelo simples dentro do testbench (latencia
// configuravel). O Flow Finalizer e um modelo que:
//   - captura flow_entry quando fin_valid sobe;
//   - responde fin_done apos FIN_LAT ciclos;
//   - MODE = 0: fin_done em pulso de 1 ciclo
//     MODE = 1: fin_done em nivel, mantido ate fin_valid cair.
//
// Bateria (por configuracao):
//   A) 12 fluxos validos + 6 entradas invalidas com lixo -> varredura 1
//   B) segunda varredura (INV=1: nada a enviar; INV=0: mesmos fluxos)
//   C) pacote normal depois das varreduras
//   D) varredura pedida com o Controller ocupado (pedido memorizado)
//   E) pacote que chega durante a varredura e ignorado
//   F) pacotes MISS/HIT normais ao final
//
// Em cada varredura confere: fluxos recebidos = entradas validas
// (mesma ordem e mesmo conteudo), numero de leituras e escritas,
// invalidacao de W0, memoria intacta fora disso, 1 pulso de scan_done.
// =====================================================================
module scan_env #(
    parameter bit INV     = 1'b1,
    parameter int MODE    = 0,
    parameter int RD_LAT  = 1,
    parameter int WR_LAT  = 1,
    parameter int FIN_LAT = 3,
    parameter bit QUIET   = 1'b0
) (
    output logic   done,
    output integer errors
);

    localparam int SC = 1024;      // entradas varridas neste teste

    localparam logic [1:0] RESULT_MISS = 2'b01;
    localparam logic [1:0] RESULT_HIT  = 2'b10;

    localparam logic [103:0] KEY_A = 104'h123456789ABCDEF123456789AB;
    localparam logic [103:0] KEY_B = 104'h00000000000000000000000001;
    localparam logic [79:0]  TS1   = 80'h0000_0000_0000_0000_1234;
    localparam logic [79:0]  TS2   = 80'h0000_0000_0000_0000_5678;

    string tag;
    initial tag = $sformatf("[SCAN INV=%0d MODE=%0d RD=%0d WR=%0d FIN=%0d]",
                            INV, MODE, RD_LAT, WR_LAT, FIN_LAT);

    logic clk = 1'b0;
    logic rst = 1'b1;

    logic [15:0]  hash_index;
    logic [103:0] flow_key;
    logic [15:0]  packet_length;
    logic [79:0]  timestamp;
    logic         hash_valid;
    logic         fin_start = 1'b0;

    logic         rd_en, rd_valid, wr_en, wr_done;
    logic [19:0]  rd_addr, wr_addr;
    logic [31:0]  rd_data, wr_data;

    logic [383:0] flow_entry;
    logic         fin_valid;
    logic         fin_done = 1'b0;
    logic         scan_done;
    logic [1:0]   lookup_result;
    logic         lookup_done;
    logic [31:0]  collision_count;

    integer read_count        = 0;
    integer write_count       = 0;
    integer start_count       = 0;
    integer lookup_done_count = 0;
    integer scan_done_count   = 0;

    logic [31:0] mem      [0:16383];
    logic [31:0] mem_snap [0:16383];

    always #5 clk = ~clk;

    controller #(.INVALIDATE_AFTER_SEND(INV), .SCAN_ENTRIES(SC)) dut (
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
        .fin_start(fin_start), .scan_done(scan_done),
        .lookup_result(lookup_result), .lookup_done(lookup_done),
        .collision_count(collision_count)
    );

    // ---------------- Modelo da Flow Table (latencia configuravel) ----------------
    logic        rd_v_sr [1:RD_LAT];
    logic [31:0] rd_d_sr [1:RD_LAT];
    logic        wr_v_sr [1:WR_LAT];
    integer      i_m;

    always @(posedge clk) begin
        if (rst) begin
            for (i_m = 1; i_m <= RD_LAT; i_m = i_m + 1) begin
                rd_v_sr[i_m] <= 1'b0;
                rd_d_sr[i_m] <= 32'b0;
            end
            for (i_m = 1; i_m <= WR_LAT; i_m = i_m + 1)
                wr_v_sr[i_m] <= 1'b0;
        end else begin
            rd_v_sr[1] <= rd_en;
            rd_d_sr[1] <= rd_en ? mem[rd_addr[13:0]] : 32'b0;
            for (i_m = 2; i_m <= RD_LAT; i_m = i_m + 1) begin
                rd_v_sr[i_m] <= rd_v_sr[i_m-1];
                rd_d_sr[i_m] <= rd_d_sr[i_m-1];
            end
            wr_v_sr[1] <= wr_en;
            for (i_m = 2; i_m <= WR_LAT; i_m = i_m + 1)
                wr_v_sr[i_m] <= wr_v_sr[i_m-1];
            if (wr_en) mem[wr_addr[13:0]] <= wr_data;
        end
    end

    assign rd_valid = rd_v_sr[RD_LAT];
    assign rd_data  = rd_d_sr[RD_LAT];
    assign wr_done  = wr_v_sr[WR_LAT];

    // ---------------- Modelo do Flow Finalizer ----------------
    logic [383:0] got [0:SC-1];
    integer       got_n     = 0;
    integer       fin_state = 0;   // 0 = livre, 1 = contando, 2 = done enviado
    integer       fin_wait  = 0;

    always @(posedge clk) begin
        if (rst) begin
            fin_done  <= 1'b0;
            fin_state <= 0;
            fin_wait  <= 0;
        end else begin
            case (fin_state)
                0: begin
                    fin_done <= 1'b0;
                    if (fin_valid) begin
                        if (got_n < SC) got[got_n] <= flow_entry;
                        else $error("%s: capacidade de captura excedida (SC=%0d)", tag, SC);
                        got_n     <= got_n + 1;
                        fin_wait  <= 1;
                        fin_state <= 1;
                    end
                end
                1: begin
                    if (fin_wait >= FIN_LAT) begin
                        fin_done  <= 1'b1;
                        fin_state <= 2;
                    end else begin
                        fin_wait <= fin_wait + 1;
                    end
                end
                default: begin
                    if (MODE == 0) fin_done <= 1'b0;      // pulso de 1 ciclo
                    if (!fin_valid) begin                 // nivel: solta quando valid cai
                        fin_done  <= 1'b0;
                        fin_state <= 0;
                    end
                end
            endcase
        end
    end

    // ---------------- Utilitarios ----------------
    task automatic fail(input string msg);
        begin
            $error("%s %s", tag, msg);
            errors = errors + 1;
        end
    endtask

    task automatic pass(input string name);
        begin
            if (!QUIET)
                $display("%s PASSOU: %s", tag, name);
        end
    endtask

    task automatic clear_counters;
        begin
            read_count        = 0;
            write_count       = 0;
            start_count       = 0;
            lookup_done_count = 0;
            scan_done_count   = 0;
        end
    endtask

    // ---------------- Monitores e checagens de protocolo ----------------
    logic         rd_en_q = 1'b0, wr_en_q = 1'b0, scan_done_q = 1'b0, fin_valid_q = 1'b0;
    logic [383:0] fe_q    = '0;
    logic         prev_idle = 1'b0;

    // Instantaneo da memoria no inicio de cada varredura (captura ate SC entradas)
    logic [383:0] exp_ent  [0:SC-1];
    logic [15:0]  exp_idx  [0:SC-1];
    logic         sent_flag [0:1023];
    integer       exp_n = 0;
    // O snapshot e calculado na borda de descida, fora do monitor de protocolo.
    // Isso evita executar loops extensos de memoria dentro do mesmo processo
    // que monitora sinais do DUT no Vivado Simulator.
    logic         snap_pending = 1'b0;
    integer       sa, se, sw;
    logic [383:0] tmp_ent;

    always @(negedge clk) begin
        if (rst) begin
            snap_pending = 1'b0;
        end else if (snap_pending) begin
            for (sa = 0; sa < 16384; sa = sa + 1)
                mem_snap[sa] = mem[sa];
            for (sa = 0; sa < SC; sa = sa + 1)
                sent_flag[sa] = 1'b0;

            exp_n = 0;
            for (se = 0; se < SC; se = se + 1) begin
                if (mem[se*16][0] === 1'b1) begin
                    tmp_ent = '0;
                    for (sw = 1; sw <= 12; sw = sw + 1)
                        tmp_ent[(sw-1)*32 +: 32] = mem[se*16 + sw];
                    if (exp_n < SC) begin
                        exp_ent[exp_n] = tmp_ent;
                        exp_idx[exp_n] = se;
                    end
                    sent_flag[se] = 1'b1;
                    exp_n = exp_n + 1;
                end
            end
            snap_pending = 1'b0;
        end
    end

    always @(posedge clk) begin
        prev_idle <= (dut.state == dut.IDLE);

        if (!rst) begin
            if (rd_en)       read_count        <= read_count + 1;
            if (wr_en)       write_count       <= write_count + 1;
            if (dut.start)   start_count       <= start_count + 1;
            if (lookup_done) lookup_done_count <= lookup_done_count + 1;
            if (scan_done)   scan_done_count   <= scan_done_count + 1;

            rd_en_q     <= rd_en;
            wr_en_q     <= wr_en;
            scan_done_q <= scan_done;
            fin_valid_q <= fin_valid;
            fe_q        <= flow_entry;

            if ((^{rd_en, wr_en, fin_valid, scan_done, lookup_done}) === 1'bx)
                fail("saida de controle com valor desconhecido (X)");
            if (rd_en && wr_en)
                fail("rd_en e wr_en ativos ao mesmo tempo");
            if (rd_en && rd_en_q)
                fail("rd_en ativo por mais de 1 ciclo");
            if (wr_en && wr_en_q)
                fail("wr_en ativo por mais de 1 ciclo");
            if (scan_done && scan_done_q)
                fail("scan_done ativo por mais de 1 ciclo");
            if (fin_valid && (rd_en || wr_en))
                fail("acesso a memoria com fin_valid ativo");
            if (fin_valid && fin_valid_q && (flow_entry !== fe_q))
                fail("flow_entry mudou com fin_valid ativo");

            // Agenda o snapshot quando o DUT entra na varredura.
            // A copia e executada no negedge pelo processo separado acima.
            if (dut.state == dut.SCAN_V_REQ && prev_idle)
                snap_pending <= 1'b1;
        end
    end

    // ---------------- Estimulos ----------------
    task automatic scramble;
        begin
            hash_index    = $urandom;
            flow_key      = {$urandom, $urandom, $urandom, $urandom};
            packet_length = $urandom;
            timestamp     = {$urandom, $urandom, $urandom};
        end
    endtask

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
            scramble();
        end
    endtask

    task automatic pulse_fin_start;
        begin
            @(negedge clk);
            fin_start = 1'b1;
            @(negedge clk);
            fin_start = 1'b0;
        end
    endtask

    task automatic wait_lookup(input integer target);
        integer t;
        begin
            t = 0;
            while (lookup_done_count < target && t < 5000) begin
                @(negedge clk);
                t = t + 1;
            end
            if (t >= 5000)
                $fatal(1, "%s TIMEOUT esperando lookup_done", tag);
            repeat (2) @(negedge clk);
        end
    endtask

    task automatic wait_scan_done(input integer target);
        integer t;
        begin
            t = 0;
            while (scan_done_count < target && t < 200000) begin
                @(negedge clk);
                t = t + 1;
            end
            if (t >= 200000)
                $fatal(1, "%s TIMEOUT esperando scan_done", tag);
        end
    endtask

    // Preload direto na memoria (Controller em IDLE)
    logic used [0:1023];

    task automatic preload_flows(input integer n_valid, input integer n_invalid);
        integer k, w;
        logic [15:0] idx;
        begin
            k = 0;
            while (k < n_valid + n_invalid) begin
                idx = $urandom_range(0, SC - 1);
                if (!used[idx] && idx != 700 && idx != 701 && idx != 900 && idx != 901) begin
                    used[idx] = 1'b1;
                    for (w = 1; w <= 15; w = w + 1)
                        mem[idx*16 + w] = $urandom;
                    mem[idx*16] = ({$urandom} & 32'hFFFFFFFE) |
                                  ((k < n_valid) ? 32'd1 : 32'd0);
                    k = k + 1;
                end
            end
        end
    endtask

    function automatic bit snap_has(input integer idx);
        integer i;
        begin
            snap_has = 1'b0;
            for (i = 0; i < exp_n && i < SC; i = i + 1)
                if (exp_idx[i] == idx) snap_has = 1'b1;
        end
    endfunction

    // ---------------- Verificacao da varredura ----------------
    task automatic verify_scan(
        input string  name,
        input bit     check_counts,
        input integer exp_starts
    );
        integer i, a, mem_bad;
        logic [31:0] expv;
        begin
            if (got_n != exp_n)
                fail($sformatf("%s: fluxos recebidos=%0d esperado=%0d", name, got_n, exp_n));
            else
                for (i = 0; i < exp_n && i < SC; i = i + 1)
                    if (got[i] !== exp_ent[i])
                        fail($sformatf("%s: fluxo %0d (indice %0d) diferente do esperado",
                                       name, i, exp_idx[i]));

            if (scan_done_count != 1)
                fail($sformatf("%s: pulsos de scan_done=%0d esperado=1", name, scan_done_count));
            if (start_count != exp_starts)
                fail($sformatf("%s: pacotes aceitos=%0d esperado=%0d", name, start_count, exp_starts));

            if (check_counts) begin
                if (read_count != SC + 12 * exp_n)
                    fail($sformatf("%s: leituras=%0d esperado=%0d", name, read_count, SC + 12 * exp_n));
                if (write_count != (INV ? exp_n : 0))
                    fail($sformatf("%s: escritas=%0d esperado=%0d", name, write_count, (INV ? exp_n : 0)));
            end

            // Memoria: igual ao instantaneo, exceto W0 das entradas enviadas (se INV)
            mem_bad = 0;
            for (a = 0; a < 16384; a = a + 1) begin
                expv = mem_snap[a];
                if (INV && (a % 16 == 0) && sent_flag[a / 16])
                    expv = 32'b0;
                if (mem[a] !== expv && mem_bad < 3) begin
                    fail($sformatf("%s: memoria[%0d] esperado=%h obtido=%h", name, a, expv, mem[a]));
                    mem_bad = mem_bad + 1;
                end
            end

            if (!QUIET) begin
                $display("%s   %s: %0d fluxo(s) enviado(s) ao Finalizer (leituras=%0d, escritas=%0d)",
                         tag, name, got_n, read_count, write_count);
                for (i = 0; i < got_n && i < exp_n && i < 4; i = i + 1)
                    $display("%s     fluxo %0d: indice=%0d chave=%h pacotes=%0d bytes=%0d",
                             tag, i, exp_idx[i], got[i][103:0], got[i][159:128], got[i][191:160]);
            end
        end
    endtask

    task automatic scan_begin;
        begin
            clear_counters();
            got_n = 0;
        end
    endtask

    task automatic scan_end(
        input string  name,
        input bit     check_counts,
        input integer exp_starts
    );
        integer e0;
        begin
            e0 = errors;
            wait_scan_done(1);
            repeat (10) @(negedge clk);
            verify_scan(name, check_counts, exp_starts);
            if (errors == e0) pass(name);
        end
    endtask

    task automatic run_scan(input string name);
        begin
            scan_begin();
            pulse_fin_start();
            scan_end(name, 1'b1, 0);
        end
    endtask

    task automatic simple_packet(
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
            wait_lookup(1);
            if (lookup_result !== exp_res)
                fail($sformatf("%s: resultado=%b esperado=%b", name, lookup_result, exp_res));
            if (mem[idx*16][0] !== 1'b1)
                fail($sformatf("%s: entrada %0d deveria estar valida", name, idx));
            if (errors == e0) pass(name);
        end
    endtask

    // ---------------- Sequencia ----------------
    integer ix;

    initial begin
        done       = 1'b0;
        errors     = 0;
        hash_index = '0;
        flow_key   = '0;
        packet_length = '0;
        timestamp  = '0;
        hash_valid = 1'b0;

        for (ix = 0; ix < 16384; ix = ix + 1) mem[ix] = 32'b0;
        for (ix = 0; ix < 1024;  ix = ix + 1) begin
            used[ix]      = 1'b0;
            sent_flag[ix] = 1'b0;
        end

        repeat (4) @(negedge clk);
        rst = 1'b0;
        repeat (2) @(negedge clk);

        // A) 12 fluxos validos + 6 entradas invalidas (com lixo)
        preload_flows(12, 6);
        run_scan("A) varredura 1: 12 fluxos validos");

        // B) segunda varredura
        // Evita expressao ternaria de strings como argumento de task automatic:
        // algumas versoes do XSim falham internamente nessa chamada.
        if (INV)
            run_scan("B) varredura 2: entradas ja invalidadas (nada a enviar)");
        else
            run_scan("B) varredura 2: mesmos fluxos (sem invalidacao)");

        // C) pacote normal depois das varreduras
        simple_packet("C) MISS idx 700 depois da varredura", 16'd700, KEY_A, 16'd100, TS1, RESULT_MISS);

        // D) varredura pedida com o Controller ocupado: pedido memorizado
        scan_begin();
        send_packet(16'd701, KEY_A, 16'd10, TS1);
        repeat (4) @(negedge clk);
        pulse_fin_start();
        scan_end("D) varredura pedida com o Controller ocupado", 1'b0, 1);
        if (!snap_has(701))
            fail("D) o fluxo do pacote 701 deveria estar na varredura");

        // E) pacote durante a varredura e ignorado
        preload_flows(5, 3);
        scan_begin();
        pulse_fin_start();
        repeat (40) @(negedge clk);                       // varredura em andamento
        send_packet(16'd900, KEY_B, 16'd5, TS2);          // deve ser ignorado
        scan_end("E) pacote durante a varredura e ignorado", 1'b1, 0);
        if (mem[16'd900*16][0] !== 1'b0)
            fail("E) a entrada 900 deveria continuar invalida");

        // F) pacotes normais ao final
        simple_packet("F) MISS idx 901", 16'd901, KEY_A, 16'd20, TS1, RESULT_MISS);
        simple_packet("F) HIT idx 901",  16'd901, KEY_A, 16'd30, TS2, RESULT_HIT);

        // G) Reset com uma varredura em andamento: nenhuma resposta pendente
        // pode sobreviver ao reset; a proxima varredura deve funcionar.
        scan_begin();
        pulse_fin_start();
        repeat (25) @(negedge clk);
        if (dut.state == dut.IDLE)
            fail("G) varredura nao estava em andamento antes do reset");
        rst = 1'b1;
        repeat (4) @(negedge clk);
        if (fin_valid !== 1'b0 || scan_done !== 1'b0 || lookup_done !== 1'b0)
            fail("G) sinais ativos durante reset da varredura");
        rst = 1'b0;
        repeat (4) @(negedge clk);
        run_scan("G) recuperacao apos reset durante leitura de varredura");

        // H) Reset enquanto o Finalizer esta processando um fluxo.
        // Recria entrada valida por escrita direta e para na fase SCAN_SEND.
        mem[16'd10*16] = 32'd1;
        mem[16'd10*16 + 1] = KEY_A[31:0];
        mem[16'd10*16 + 2] = KEY_A[63:32];
        mem[16'd10*16 + 3] = KEY_A[95:64];
        mem[16'd10*16 + 4] = {24'b0, KEY_A[103:96]};
        scan_begin();
        pulse_fin_start();
        begin : wait_finalizer_reset
            integer t;
            t = 0;
            while (!fin_valid && t < 2000) begin
                @(negedge clk);
                t = t + 1;
            end
            if (t == 2000) $fatal(1, "%s H) timeout aguardando fin_valid", tag);
        end
        rst = 1'b1;
        repeat (4) @(negedge clk);
        if (fin_valid !== 1'b0 || scan_done !== 1'b0)
            fail("H) fin_valid/scan_done permaneceram ativos durante reset");
        rst = 1'b0;
        repeat (4) @(negedge clk);
        run_scan("H) recuperacao apos reset durante handshake Finalizer");

        done = 1'b1;
    end

endmodule


// =====================================================================
// Topo unico:
//   - unit_env : caminho do pacote (MISS/HIT/COLLISION) em 4 configuracoes
//                de latencia da memoria (leitura / escrita, em ciclos)
//   - scan_env : varredura / finalizacao (PROVISORIO) em 3 configuracoes
// =====================================================================
module tb_controller_unit;

    logic [7:0] done;
    integer     e_u0, e_u1, e_u2, e_u3, e_full;     // pacote
    integer     e_s0, e_s1, e_s2;           // varredura
    integer     err_pacote, err_scan, total;

    // ---------------- Caminho do pacote ----------------
    unit_env #(.RD_LAT(1), .WR_LAT(1))                 env_1_1 (.done(done[0]), .errors(e_u0));
    unit_env #(.RD_LAT(2), .WR_LAT(1), .QUIET(1'b1))   env_2_1 (.done(done[1]), .errors(e_u1));
    unit_env #(.RD_LAT(1), .WR_LAT(3), .QUIET(1'b1))   env_1_3 (.done(done[2]), .errors(e_u2));
    unit_env #(.RD_LAT(3), .WR_LAT(2), .QUIET(1'b1))   env_3_2 (.done(done[3]), .errors(e_u3));

    // Cobertura do espaco de enderecos completo, sem multiplicar a memoria das outras instancias.
    unit_env #(.RD_LAT(1), .WR_LAT(1), .N_RANDOM(50), .FULL_RANGE(1'b1)) env_full (.done(done[7]), .errors(e_full));

    // ---------------- Varredura / finalizacao ----------------
    //                 INV         MODE      RD          WR          FIN
    scan_env #(.INV(1'b1), .MODE(0), .RD_LAT(1), .WR_LAT(1), .FIN_LAT(3))                  env_scan_a (.done(done[4]), .errors(e_s0));
    scan_env #(.INV(1'b1), .MODE(1), .RD_LAT(2), .WR_LAT(2), .FIN_LAT(1), .QUIET(1'b1))    env_scan_b (.done(done[5]), .errors(e_s1));
    scan_env #(.INV(1'b0), .MODE(0), .RD_LAT(1), .WR_LAT(3), .FIN_LAT(5), .QUIET(1'b1))    env_scan_c (.done(done[6]), .errors(e_s2));

    initial begin
        err_pacote = 0; err_scan = 0; total = 0;
        wait (done === 8'hFF);
        #20;
        err_pacote = e_u0 + e_u1 + e_u2 + e_u3 + e_full;
        err_scan   = e_s0 + e_s1 + e_s2;
        total      = err_pacote + err_scan;

        $display("Resumo: pacote = %0d erro(s) | varredura = %0d erro(s)", err_pacote, err_scan);
        if (total == 0)
            $display("TODOS OS TESTES UNITARIOS PASSARAM! (pacote: 4 configuracoes + enderecos completos; varredura: 3 configuracoes)");
        else
            $display("TESTES UNITARIOS FINALIZADOS COM %0d ERRO(S).", total);
        $finish;
    end

    initial begin
        #200000000;
        $fatal(1, "TIMEOUT global");
    end

endmodule