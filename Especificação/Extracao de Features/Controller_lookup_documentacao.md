# Controller – Recepção de metadados e solicitação de LOOKUP

## 1. `controller.sv` — Módulo do Controller

### Objetivo

Implementa a etapa inicial do Controller. Nesta fase o módulo:

1. recebe o `hash_index` do pacote, acompanhado do sinal `hash_valid`, vindo da etapa de Extração de Metadados;
2. calcula, a partir do `hash_index`, o endereço-base do registro de fluxo na Flow Table;
3. percorre a FSM de LOOKUP, emitindo uma solicitação de leitura (`rd_en` + `rd_addr`) para cada palavra do registro;
4. armazena as palavras lidas em `flow_entry`.

A decisão de HIT/MISS/colisão, as escritas e a interface com o Finalizer não fazem parte desta etapa.

### Organização da Flow Table

- 65.536 entradas × 16 palavras × 32 bits (1.048.576 palavras no total).
- Endereço-base da entrada: `base_addr = hash_index × 16`.
- Endereço de cada palavra lida: `rd_addr = base_addr + word_index`.

Como 16 é potência de 2, a multiplicação é feita por deslocamento:

```systemverilog
base_addr <= {1'b0, hash_index, 4'b0000};   // hash_index * 16
```

O resultado ocupa 20 bits. O bit extra à esquerda (`1'b0`) completa a largura de 21 bits usada em `base_addr` e `rd_addr`, e nunca estoura, pois o maior valor possível é 65535 × 16 = 1.048.560.

### Elementos internos

| Elemento | Descrição |
|---|---|
| `state_t` | Enum de 2 bits com os estados `IDLE`, `LOOKUP_REQ`, `LOOKUP_WAIT` e `LOOKUP_DONE`. |
| `state` | Registrador de estado da FSM. |
| `base_addr[20:0]` | Endereço-base da entrada, calculado e registrado quando o pacote é aceito. |
| `word_index[2:0]` | Índice da palavra em leitura (0 a 4). |

### Interface

| Sinal | Direção | Largura | Descrição |
|---|---|---|---|
| `clk` | Entrada | 1 | Clock; as operações ocorrem na borda de subida. |
| `reset` | Entrada | 1 | Reset síncrono, ativo em nível alto. |
| `hash_index` | Entrada | 16 | Índice da entrada na Flow Table. |
| `flow_key` | Entrada | 104 | Chave do fluxo (metadado). Conectada, ainda não utilizada nesta etapa. |
| `packet_length` | Entrada | 16 | Tamanho do pacote (metadado). Conectada, ainda não utilizada nesta etapa. |
| `timestamp` | Entrada | 80 | Instante de chegada do pacote (metadado). Conectada, ainda não utilizada nesta etapa. |
| `hash_valid` | Entrada | 1 | Indica que os metadados são válidos; só é considerado em `IDLE`. |
| `rd_en` | Saída | 1 | Solicitação de leitura à Flow Table. |
| `rd_addr` | Saída | 21 | Endereço da palavra a ler. |
| `rd_data` | Entrada | 32 | Palavra retornada pela Flow Table. |
| `rd_valid` | Entrada | 1 | Indica que `rd_data` é válido. |
| `flow_entry` | Saída | 384 | Registro lido; a palavra `k` ocupa os bits `[k*32 +: 32]`. |

### Funcionamento

**Bloco combinacional de saídas (`always_comb`).** `rd_en` e `rd_addr` recebem valor padrão zero, o que evita latches. Somente em `LOOKUP_REQ` o módulo ativa `rd_en = 1` e `rd_addr = base_addr + word_index`. Em qualquer outro estado não há solicitação.

**Bloco sequencial (`always_ff`).** Contém a FSM e o registro dos dados. Com `reset = 1`, o estado volta a `IDLE` e `base_addr`, `word_index` e `flow_entry` são zerados.

| Estado | O que acontece | Próximo estado |
|---|---|---|
| `IDLE` | `word_index` é zerado. Se `hash_valid = 1`, registra `base_addr = {1'b0, hash_index, 4'b0000}` e limpa `flow_entry`. | `LOOKUP_REQ` (se `hash_valid`) |
| `LOOKUP_REQ` | Por 1 ciclo, a lógica combinacional mantém `rd_en = 1` com o endereço da palavra atual. | `LOOKUP_WAIT` |
| `LOOKUP_WAIT` | Espera `rd_valid`. Ao chegar, grava `rd_data` em `flow_entry[word_index*32 +: 32]`. Se `word_index == 4`, encerra; senão, incrementa `word_index`. | `LOOKUP_DONE` ou `LOOKUP_REQ` |
| `LOOKUP_DONE` | Lookup concluído (aqui entrará, nas próximas etapas, o tratamento de HIT/MISS/colisão). | `IDLE` |

O LOOKUP lê 5 palavras por pacote (`word_index` de 0 a 4), em endereços consecutivos a partir do endereço-base.

O avanço de uma palavra para a próxima depende de `rd_valid`, e não de uma contagem fixa de ciclos. Por isso, a FSM continua correta mesmo que a latência da memória seja alterada.

Como `flow_entry` é limpo ao aceitar um novo pacote, os bits não preenchidos (`[383:160]`) permanecem em zero e não carregam dados de um lookup anterior.

---

## 2. `tb_controller.sv` — Testbench

### Objetivo

Verifica, com metadados de pacotes simulados, se:

1. o `hash_index` aceito produz o endereço-base correto (`hash_index × 16`);
2. para cada entrada válida, o Controller gera exatamente 5 solicitações de leitura, em endereços consecutivos a partir da base;
3. as palavras retornadas pela memória são armazenadas em `flow_entry` na posição correta;
4. os bits não utilizados de `flow_entry` permanecem em zero.

### Configuração e conexão

A testbench declara os sinais, instancia o `controller` como `dut` e conecta todas as portas pelo nome. Também descreve um **modelo simplificado da Flow Table**: um array `memory[0:4095]` de palavras de 32 bits, com leitura síncrona. Todo o array é inicializado com zero no início da simulação.

### Clock

```systemverilog
always #5 clk = ~clk;
```

Inverte o clock a cada 5 ns, produzindo período de 10 ns.

### Modelo de memória

- Uma requisição (`rd_en`) amostrada em uma borda de subida é guardada em `pending_read` e `pending_addr`.
- Na borda seguinte, `rd_data` recebe `memory[pending_addr]` e `rd_valid` vai para 1 por um ciclo.

Assim, o dado e o `rd_valid` chegam dois ciclos depois do início da solicitação, comportamento semelhante ao de uma memória síncrona.

### Monitor de endereços

A cada borda de subida com `rd_en = 1`, o monitor compara `rd_addr` com `expected_base + reads_seen`. Se houver divergência, emite `$error` e incrementa `errors`. Em seguida incrementa `reads_seen`. Cada endereço emitido pelo Controller é, portanto, conferido individualmente e na ordem correta.

### Tarefa `run_lookup(test_hash)`

1. Aguarda, na borda de descida do clock, o Controller estar em `IDLE`.
2. Define `expected_base = {1'b0, test_hash, 4'b0000}`, zera `reads_seen` e grava na memória cinco palavras de teste: `memory[base + j] = 32'hA0000000 + j`, com `j` de 0 a 4.
3. Aplica `hash_index`, `flow_key`, `packet_length` e `timestamp` e ativa `hash_valid` por um ciclo.
4. Aguarda `dut.state == dut.LOOKUP_DONE`.
5. Verifica:
   - cada palavra `W0` a `W4` de `flow_entry` contra `0xA0000000 + j`;
   - bits `[383:160]` de `flow_entry` iguais a zero;
   - total de leituras igual a 5.
6. Imprime `PASSOU` quando `errors == 0` e espera um ciclo antes do próximo teste.

Cada palavra da memória tem um valor distinto (`A0000000`, `A0000001`, ...). Se uma palavra fosse gravada na posição errada de `flow_entry`, ou em ordem trocada, a comparação detectaria o erro.

Metadados aplicados nos testes: `flow_key = 0x123456789ABCDEF123456789AB`, `packet_length = 128` (`0x0080`) e `timestamp = 1234` (`0x04D2`), iguais nos três testes.

### Sequência de testes

Após manter `reset` em 1 por 3 ciclos, a testbench o libera e executa:

| Teste | `hash_index` | Base esperada (`hash × 16`) | Endereços de leitura esperados |
|---|---|---|---|
| 1 | 0 | 0 (`0x000`) | 0, 1, 2, 3, 4 |
| 2 | 5 | 80 (`0x050`) | 80, 81, 82, 83, 84 |
| 3 | 100 (`0x64`) | 1600 (`0x640`) | 1600, 1601, 1602, 1603, 1604 |

Os valores cobrem o menor índice possível (0), um índice pequeno (5) e um índice maior (100), com base não trivial. Ao final, a testbench imprime `TODOS OS TESTES PASSARAM!` se `errors == 0`, ou o número de erros caso contrário, e chama `$finish`. Um timeout global de 100 µs usa `$fatal` caso o lookup não termine.

---

## 3. Forma de onda

![Forma de onda – sinais do Controller e do modelo de memória](imagens/waveform_1.png)

![Forma de onda – contadores de verificação e endereço esperado](imagens/waveform_2.png)

A simulação mostra os três LOOKUPs consecutivos em cerca de 590 ns.

### Sequência de um LOOKUP (teste 1, hash = 0)

Os instantes abaixo decorrem do código e do período de clock de 10 ns, e são consistentes com a forma de onda.

| Instante | Evento |
|---|---|
| 30 ns | `reset` é liberado. |
| 40 ns | `hash_valid` sobe junto com os metadados (borda de descida). |
| 45 ns | Borda de subida: o Controller registra `base_addr` e vai para `LOOKUP_REQ`. |
| 45–55 ns | `rd_en = 1` com `rd_addr = base + 0`. |
| 55 ns | O modelo amostra a requisição (`pending_read = 1`); o Controller vai para `LOOKUP_WAIT`. |
| 65 ns | `rd_valid = 1` e `rd_data = A0000000`. |
| 75 ns | O Controller grava W0 em `flow_entry` e volta para `LOOKUP_REQ` com `word_index = 1`. |
| 75, 105, 135, 165 ns | Início das requisições das palavras 1 a 4 (uma a cada 30 ns). |
| 195 ns | Grava W4 e entra em `LOOKUP_DONE`. |
| 205 ns | Retorna a `IDLE`. |

### O que se observa na forma de onda

- **Entrada do pacote.** `hash_valid` gera um pulso de um ciclo por teste. `hash_index` assume `0000`, `0005` e `0064` (hexadecimal), isto é, 0, 5 e 100.
- **Solicitações de leitura.** Após cada pulso de `hash_valid`, `rd_en` gera cinco pulsos de um ciclo, separados por 3 ciclos (30 ns): 1 ciclo em `LOOKUP_REQ` e 2 em `LOOKUP_WAIT`.
- **Endereços.** `expected_base` assume `000000`, `000050` e `000640` (hexadecimal), que correspondem a 0, 80 e 1600. `rd_addr` percorre a sequência a partir da base de cada teste, e `pending_addr` o acompanha com um ciclo de atraso; os últimos valores observados são `000004`, `000054` e `000644`, ou seja, `base + 4`.
- **Resposta da memória.** `pending_read` sobe um ciclo depois de `rd_en`, e `rd_valid` um ciclo depois de `pending_read`. `rd_data` mostra `a0000000` a `a0000004`.
- **Armazenamento.** `flow_entry` é atualizado a cada `rd_valid`, uma palavra por vez.
- **Contadores de verificação.** `errors` permanece em `00000000` durante toda a simulação. `reads_seen` chega a `00000005` em cada teste, e a variável de inicialização `i` termina em `00001000` (4096), indicando que toda a memória foi inicializada antes dos testes.

---

## 4. Por que o resultado está correto

| Requisito do escopo | Evidência |
|---|---|
| Criar o módulo RTL | `controller.sv` compila e simula junto com o testbench, com as portas conectadas pelo nome. |
| Receber os metadados | O `hash_index` é aceito apenas em `IDLE` com `hash_valid = 1`. Os endereços de leitura, derivados dele, coincidem com os esperados nos três testes. |
| Lógica inicial da FSM | A sequência `IDLE → LOOKUP_REQ → LOOKUP_WAIT → (LOOKUP_REQ ...) → LOOKUP_DONE → IDLE` é percorrida nos três testes; o testbench só avança quando o estado volta a `IDLE`. |
| Calcular os endereços a partir do `hash_index` | `base_addr = {1'b0, hash_index, 4'b0000}`. Os hashes 0, 5 e 100 resultam em 0, 80 e 1600, conferidos pelo monitor a cada leitura. |
| Gerar a lista de endereços do registro | `rd_addr = base_addr + word_index`, com `word_index` de 0 a 4: cinco endereços consecutivos por LOOKUP. |
| Gerar a solicitação de LOOKUP para cada entrada válida | Cada `hash_valid` aceito produz exatamente 5 pulsos de `rd_en` (`reads_seen = 5`); nenhum `rd_en` é emitido fora de `LOOKUP_REQ`. |
| Armazenar corretamente o registro lido | `W0` a `W4` de `flow_entry` coincidem com `A0000000` a `A0000004`, e os bits `[383:160]` permanecem em zero. |
| Resultado global | `errors = 0` ao final da simulação. |

---

## 5. Limitações desta etapa e próximos passos

- Apenas o `hash_index` é registrado e utilizado. `flow_key`, `packet_length` e `timestamp` já estão conectados na interface, mas ainda não são armazenados pelo Controller; serão necessários na etapa de comparação de chave e atualização do registro.
- O Controller não possui sinal de `ready`: um `hash_valid` recebido fora de `IDLE` é ignorado. O testbench evita isso aguardando `dut.state == IDLE` antes de aplicar cada pacote. Um handshake `in_valid`/`in_ready` poderá ser adicionado na integração.
- `rd_addr` tem 21 bits, enquanto a Flow Table comportamental utiliza endereço de 20 bits (`ADDR_WIDTH = 20`). O bit mais significativo é sempre zero; na integração, a largura deve ser alinhada (por exemplo, ligando apenas `rd_addr[19:0]`).
- O tratamento de HIT, MISS e colisão, as escritas na Flow Table e a interface com o Finalizer serão implementados nas próximas etapas.
- O testbench usa um modelo próprio de memória; a integração com o módulo `flow_table.sv` fica para a etapa de integração.
