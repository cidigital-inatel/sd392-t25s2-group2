# Flow Table – Testes iniciais

## 1. `flow_table.sv` — Módulo da Flow Table

### Objetivo
Implementa uma memória comportamental síncrona para armazenar palavras de 32 bits. O módulo recebe endereços físicos e executa operações de leitura e escrita.

### Organização
- `ADDR_WIDTH = 20`: largura do endereço.
- `DATA_WIDTH = 32`: largura de cada palavra.
- `DEPTH = 1 << ADDR_WIDTH`: profundidade padrão de 1.048.576 palavras.
- `mem[0:DEPTH-1]`: array que representa a memória.

A organização lógica considerada no projeto é de 65.536 entradas, com 16 palavras de 32 bits por entrada. O módulo recebe o endereço físico da palavra.

### Interface

| Sinal | Direção | Descrição |
|---|---|---|
| `clk` | Entrada | Clock; operações ocorrem na borda de subida. |
| `rst` | Entrada | Reset síncrono dos sinais de controle. |
| `rd_en` | Entrada | Habilita uma leitura. |
| `rd_addr` | Entrada | Endereço da palavra a ler. |
| `rd_data` | Saída | Dado retornado pela leitura. |
| `rd_valid` | Saída | Recebe o valor de `rd_en` a cada ciclo ativo. |
| `wr_en` | Entrada | Habilita uma escrita. |
| `wr_addr` | Entrada | Endereço da palavra a escrever. |
| `wr_data` | Entrada | Dado a ser escrito. |
| `wr_done` | Saída | Recebe o valor de `wr_en` a cada ciclo ativo. |

### Funcionamento

O bloco `always_ff @(posedge clk)` descreve a lógica sequencial:

- **Reset (`rst = 1`):** define `rd_data`, `rd_valid` e `wr_done` como zero. Não limpa o array `mem`.
- **Leitura (`rd_en = 1`):** agenda `mem[rd_addr]` para `rd_data`. `rd_valid` recebe `1` na mesma borda de clock.
- **Escrita (`wr_en = 1`):** grava `wr_data` em `mem[wr_addr]`. `wr_done` recebe `1` na mesma borda de clock.
- **Sem solicitação:** `rd_valid` e `wr_done` recebem zero, pois acompanham `rd_en` e `wr_en`. `rd_data` mantém o último valor quando não há leitura.

As atribuições não bloqueantes (`<=`) são utilizadas para atualizar os sinais sequenciais. A memória não é inicializada; ler uma posição antes de escrevê-la pode produzir `X` na simulação.

---

## 2. `flow_table_tb.sv` — Testbench

### Objetivo
Testa o módulo `flow_table` por simulação, aplicando sinais de controle e verificando os dados lidos e os sinais de conclusão.

### Configuração e conexão
A testbench declara os sinais de entrada e saída, instancia o módulo sob teste (`dut`) e conecta cada sinal à porta correspondente. Os parâmetros usados são `ADDR_WIDTH = 20` e `DATA_WIDTH = 32`.

### Clock

```systemverilog
always #5 clk = ~clk;
```

Inverte o clock a cada 5 ns, produzindo período de 10 ns.

### Tarefa `write_word(addr, data)`

1. Aguarda a borda de descida do clock.
2. Ativa `wr_en` e aplica endereço e dado.
3. Aguarda a borda de subida e verifica `wr_done`.
4. Desativa `wr_en`.
5. Verifica que `wr_done` voltou para zero.

Se uma verificação falhar, `$fatal` encerra a simulação com uma mensagem de erro.

### Tarefa `read_and_check(addr, expected)`

1. Aguarda a borda de descida do clock.
2. Ativa `rd_en` e aplica o endereço.
3. Aguarda a borda de subida e verifica `rd_valid`.
4. Compara `rd_data` com o valor esperado usando `!==`.
5. Desativa `rd_en` e verifica que `rd_valid` voltou para zero.

O operador `!==` também detecta valores desconhecidos (`X`) e alta impedância (`Z`).

### Sequência de testes

Após manter `rst` ativo por dois ciclos de clock, a testbench o desativa e executa:

| Etapa | Operação | Endereço | Dado esperado |
|---|---|---:|---|
| 1 | Escrever e ler | 80 (`0x50`) | `0x1234ABCD` |
| 2 | Escrever e ler | 81 (`0x51`) | `0xDEADBEEF` |

Ao final, a testbench imprime `Fim.` e chama `$finish`. Se alguma verificação falhar, `$fatal` interrompe a execução antes do encerramento normal.

### Forma de onda

A forma de onda da simulação ilustra os sinais de clock e reset, as solicitações de leitura e escrita, os endereços e dados aplicados, e os sinais `rd_valid` e `wr_done`. Os dados lidos correspondem aos valores escritos nos endereços testados.

![Forma de onda dos testes iniciais da Flow Table](https://raw.githubusercontent.com/cidigital-inatel/sd392-t25s2-group2/main/docs/images/Flow_Table_testes_iniciais_waveform.png)
