// Testbench que le o arquivo de estimulos (stream_words.txt) e reproduz,
// na interface do DUT mockup, as transferencias que seriam realizadas pelo
// MAC de referencia: TDATA, TKEEP, TVALID, TLAST e TUSER, respeitando o
// handshake com TREADY e reproduzindo temporalmente o espacamento entre
// pacotes a partir do timestamp de cada um.

`timescale 1ns/1ps

module tb_stimuli_axis;

    parameter time CLK_PERIOD_NS   = 10ns;
    parameter int  MAX_IDLE_CYCLES = 100;

    logic        clk    = 0;
    logic        rst_n  = 0;
    logic        tvalid = 0;
    logic [63:0] tdata  = '0;
    logic [7:0]  tkeep  = '0;
    logic        tlast  = 0;
    logic        tuser  = 0;
    logic        tready;

    logic [31:0] total_packets;
    logic [31:0] total_bytes;
    logic [31:0] invalid_frames;

    always #(CLK_PERIOD_NS/2) clk = ~clk;

    dut_mockup dut (
        .clk(clk),
        .rst_n(rst_n),
        .tvalid(tvalid),
        .tready(tready),
        .tdata(tdata),
        .tkeep(tkeep),
        .tlast(tlast),
        .tuser(tuser),
        .total_packets(total_packets),
        .total_bytes(total_bytes),
        .invalid_frames(invalid_frames)
    );

    // Leitura do arquivo de estimulos para arrays dinamicos
    longint unsigned ts_arr   [$];
    logic [63:0]     data_arr [$];
    bit              valid_arr[$];
    bit              sop_arr  [$];
    bit              eop_arr  [$];
    logic [7:0]      keep_arr [$];
    bit              tuser_arr[$];

    task automatic ler_arquivo_estimulos(input string caminho);
        int fd;
        reg [8*300-1:0] linha;
        longint unsigned ts_val;
        logic [63:0] data_val;
        int valid_val, sop_val, eop_val, tuser_val;
        logic [7:0] keep_val;
        int r;
        begin
            fd = $fopen(caminho, "r");
            if (fd == 0) begin
                $fatal(1, "Nao foi possivel abrir o arquivo de estimulos: %s", caminho);
            end
            while (!$feof(fd)) begin
                r = $fgets(linha, fd);
                if (r != 0 && linha[8*300-1 -: 8] != "#") begin
                    r = $sscanf(linha, "%d %h %d %d %d %h %d",
                        ts_val, data_val, valid_val, sop_val, eop_val, keep_val, tuser_val);
                    if (r == 7) begin
                        ts_arr.push_back(ts_val);
                        data_arr.push_back(data_val);
                        valid_arr.push_back(valid_val[0]);
                        sop_arr.push_back(sop_val[0]);
                        eop_arr.push_back(eop_val[0]);
                        keep_arr.push_back(keep_val);
                        tuser_arr.push_back(tuser_val[0]);
                    end
                end
            end
            $fclose(fd);
            $display("[TB] %0d words lidas de %s", ts_arr.size(), caminho);
        end
    endtask

    function automatic int popcount8(input logic [7:0] v);
        int c;
        begin
            c = 0;
            for (int i = 0; i < 8; i++) if (v[i]) c++;
            popcount8 = c;
        end
    endfunction

    // Scoreboard de referencia 
    int unsigned ref_packets = 0;
    int unsigned ref_bytes   = 0;
    int unsigned ref_invalid = 0;

    task automatic transmitir_estimulos();
        int i;
        int n;
        int idle_cycles;
        longint signed delta_ns;
        bit pacote_invalido;
        begin
            n = ts_arr.size();
            pacote_invalido = 0;
            i = 0;
            while (i < n) begin
                // aplica a word atual e mantem estavel ate o handshake ocorrer
                tvalid <= 1'b1;
                tdata  <= data_arr[i];
                tkeep  <= keep_arr[i];
                tlast  <= eop_arr[i];
                tuser  <= tuser_arr[i];
                @(posedge clk);
                while (!(tvalid && tready)) @(posedge clk);

                // contabiliza no scoreboard de referencia
                ref_bytes += popcount8(keep_arr[i]);
                if (!tuser_arr[i]) pacote_invalido = 1;

                if (eop_arr[i]) begin
                    ref_packets += 1;
                    if (pacote_invalido) ref_invalid += 1;
                    pacote_invalido = 0;
                end

                // calcula o espacamento ate a proxima word para reproduzir
                // temporalmente as transferencias do MAC
                if (i+1 < n && eop_arr[i]) begin
                    delta_ns = ts_arr[i+1] - ts_arr[i];
                    idle_cycles = int'(delta_ns / CLK_PERIOD_NS);
                    if (idle_cycles > MAX_IDLE_CYCLES) begin
                        idle_cycles = MAX_IDLE_CYCLES; // capado p/ viabilizar a simulacao
                    end
                    tvalid <= 1'b0;
                    repeat (idle_cycles) @(posedge clk);
                end
                i++;
            end
            tvalid <= 1'b0;
            @(posedge clk);
        end
    endtask

    function automatic bit total_invalid_ok();
        total_invalid_ok = (invalid_frames === ref_invalid);
    endfunction

    // Sequencia principal
    string arquivo_estimulos;

    initial begin
        if (!$value$plusargs("STIMULI=%s", arquivo_estimulos))
            arquivo_estimulos = "stream_words.txt";

        ler_arquivo_estimulos(arquivo_estimulos);

        rst_n = 0;
        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        transmitir_estimulos();

        // tempo para o DUT contabilizar a ultima word
        repeat (5) @(posedge clk);
        $display("[TB]  pacotes esperados : %0d | bytes esperados : %0d | invalidos esperados: %0d",
            ref_packets, ref_bytes, ref_invalid);
        $display("[DUT] pacotes recebidos : %0d | bytes recebidos : %0d | invalidos recebidos: %0d",
            total_packets, total_bytes, invalid_frames);

        if (total_packets === ref_packets && total_bytes === ref_bytes && total_invalid_ok())
            $display("RESULTADO: PASS -- fluxo de leitura/conversao/transmissao validado no mockup.");
        else
            $display("RESULTADO: FAIL -- divergencia entre o esperado e o recebido pelo DUT mockup.");

        $finish;
    end

endmodule
