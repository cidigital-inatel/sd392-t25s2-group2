`timescale 1ns/1ps
`default_nettype none

module packet_parser_tb;

    // Timestamp do PCAP em microssegundos.
    localparam int TS_WIDTH = 64;

    logic clk;
    logic reset_n;

    logic [63:0] TDATA;
    logic [7:0]  TKEEP;
    logic        TVALID;
    logic        TLAST;
    logic        TUSER;
    logic [TS_WIDTH-1:0] timestamp_in;

    logic [31:0] src_ip;
    logic [31:0] dst_ip;
    logic [15:0] src_port;
    logic [15:0] dst_port;
    logic [7:0]  protocol;
    logic [15:0] packet_length;
    logic [TS_WIDTH-1:0] timestamp;
    logic        metadata_valid;

    integer fd;
    integer rc;
    integer timeout;
    integer first_transfer_seen;

    reg [1023:0] header_line;
    reg [63:0] file_tdata;
    reg [7:0]  file_tkeep;
    integer    file_tvalid;
    integer    file_tlast;
    integer    file_tuser;
    reg [63:0] file_timestamp;

    reg [63:0] expected_timestamp;

    packet_parser #(
        .TS_WIDTH(TS_WIDTH)
    ) dut (
        .clk(clk),
        .reset_n(reset_n),
        .TDATA(TDATA),
        .TKEEP(TKEEP),
        .TVALID(TVALID),
        .TLAST(TLAST),
        .TUSER(TUSER),
        .timestamp_in(timestamp_in),
        .src_ip(src_ip),
        .dst_ip(dst_ip),
        .src_port(src_port),
        .dst_port(dst_port),
        .protocol(protocol),
        .packet_length(packet_length),
        .timestamp(timestamp),
        .metadata_valid(metadata_valid)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task automatic check_result;
        integer errors;
        begin
            errors = 0;

            if (src_ip !== 32'hC0A8010A) begin
                $display("ERRO src_ip: esperado C0A8010A, recebido %08h", src_ip);
                errors = errors + 1;
            end else
                $display("PASS src_ip        = %08h", src_ip);

            if (dst_ip !== 32'h08080808) begin
                $display("ERRO dst_ip: esperado 08080808, recebido %08h", dst_ip);
                errors = errors + 1;
            end else
                $display("PASS dst_ip        = %08h", dst_ip);

            if (src_port !== 16'd52100) begin
                $display("ERRO src_port: esperado 52100, recebido %0d", src_port);
                errors = errors + 1;
            end else
                $display("PASS src_port      = %0d", src_port);

            if (dst_port !== 16'd443) begin
                $display("ERRO dst_port: esperado 443, recebido %0d", dst_port);
                errors = errors + 1;
            end else
                $display("PASS dst_port      = %0d", dst_port);

            if (protocol !== 8'd6) begin
                $display("ERRO protocol: esperado 6, recebido %0d", protocol);
                errors = errors + 1;
            end else
                $display("PASS protocol      = %0d", protocol);

            if (packet_length !== 16'd40) begin
                $display("ERRO packet_length: esperado 40, recebido %0d",
                         packet_length);
                errors = errors + 1;
            end else
                $display("PASS packet_length = %0d", packet_length);

            // Nao ha mais valor fixo "1000".
            // O valor esperado e lido da primeira transferencia do arquivo.
            if (timestamp !== expected_timestamp) begin
                $display("ERRO timestamp: esperado %0d us, recebido %0d us",
                         expected_timestamp, timestamp);
                errors = errors + 1;
            end else
                $display("PASS timestamp     = %0d us", timestamp);

            if (errors == 0)
                $display("\nPASS: PCAP -> estimulos -> MAC RX -> Packet Parser funcionando.\n");
            else begin
                $display("\nFAIL: %0d erro(s) encontrado(s).\n", errors);
                $fatal(1);
            end
        end
    endtask

    initial begin
        reset_n            = 1'b0;
        TDATA              = 64'd0;
        TKEEP              = 8'd0;
        TVALID             = 1'b0;
        TLAST              = 1'b0;
        TUSER              = 1'b0;
        timestamp_in       = '0;
        expected_timestamp = '0;
        first_transfer_seen = 0;

        repeat (3) @(posedge clk);
        reset_n = 1'b1;

        fd = $fopen("input_stream.txt", "r");
        if (fd == 0)
            $fatal(1, "Nao foi possivel abrir input_stream.txt");

        // O arquivo gerado pelo Python possui cabecalho.
        // Descarta a primeira linha antes de usar $fscanf.
        rc = $fgets(header_line, fd);

        // Formato:
        // TDATA TKEEP TVALID TLAST TUSER TIMESTAMP
        while (!$feof(fd)) begin
            rc = $fscanf(
                fd,
                "%h %h %d %d %d %d\n",
                file_tdata,
                file_tkeep,
                file_tvalid,
                file_tlast,
                file_tuser,
                file_timestamp
            );

            if (rc == 6) begin
                // Timestamp esperado = timestamp associado ao inicio do pacote.
                if (!first_transfer_seen) begin
                    expected_timestamp = file_timestamp;
                    first_transfer_seen = 1;
                end

                @(negedge clk);
                TDATA        = file_tdata;
                TKEEP        = file_tkeep;
                TVALID       = file_tvalid[0];
                TLAST        = file_tlast[0];
                TUSER        = file_tuser[0];
                timestamp_in = file_timestamp;
            end
        end

        @(negedge clk);
        TVALID       = 1'b0;
        TLAST        = 1'b0;
        TUSER        = 1'b0;
        TKEEP        = 8'h00;
        TDATA        = 64'h0;
        timestamp_in = '0;

        $fclose(fd);

        if (!first_transfer_seen)
            $fatal(1, "Nenhuma transferencia valida foi lida de input_stream.txt");

        timeout = 0;
        while (!metadata_valid && timeout < 20) begin
            @(posedge clk);
            timeout = timeout + 1;
        end

        if (!metadata_valid)
            $fatal(1, "Timeout: metadata_valid nao foi gerado");

        check_result();

        @(posedge clk);
        if (metadata_valid !== 1'b0)
            $fatal(1, "metadata_valid deveria retornar a 0 apos um ciclo");

        $finish;
    end

endmodule

`default_nettype wire
