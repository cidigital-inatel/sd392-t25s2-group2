# Controller — Recepção de metadados e solicitação de LOOKUP

## 1. `controller.sv` — Módulo do Controller

### Objetivo

Implementa a etapa inicial do Controller, responsável por iniciar a busca de uma entrada na Flow Table e armazenar as palavras retornadas pela memória.

Nesta etapa, o módulo:

- Recebe `hash_index`, acompanhado de `hash_valid`, proveniente da etapa de Extração de Metadados.
- Calcula o endereço-base da entrada na Flow Table.
- Executa a FSM de LOOKUP, emitindo solicitações de leitura por meio de `rd_en` e `rd_addr`.
- Armazena as cinco palavras lidas em `flow_entry`.

A comparação de `flow_key`, a decisão de HIT/MISS/colisão, as operações de escrita e a interface com o Flow Finalizer não fazem parte desta etapa.

### 1.1. Organização da Flow Table

A organização lógica prevista para a Flow Table é:

- **65.536 entradas**.
- **16 palavras de 32 bits por entrada**.
- **512 bits por entrada**.
- **1.048.576 palavras de 32 bits no total**.

O endereço-base de uma entrada é calculado por:

```systemverilog
base_addr <= {1'b0, hash_index, 4'b0000};
```

Essa operação equivale a:

\[
base\_addr = hash\_index \times 16
\]

O endereço de cada palavra solicitada é:

```systemverilog
rd_addr = base_addr + word_index;
```

Como cada entrada possui 16 palavras, o deslocamento de quatro bits calcula o endereço-base sem a necessidade de um multiplicador.

O sinal `base_addr` possui 21 bits, conforme a interface atual do Controller. Entretanto, os endereços válidos da organização descrita cabem em 20 bits, pois o maior endereço de palavra é 1.048.575. O bit mais significativo de `base_addr` permanece zero.

**Escopo atual:** o Controller solicita somente as palavras W0 a W4. As demais palavras da entrada não são lidas nesta etapa.

### 1.2. Elementos internos

| Elemento | Descrição |
|---|---|
| `state_t` | Tipo enumerado de 2 bits que define os estados da FSM. |
| `state` | Registrador que armazena o estado atual. |
| `base_addr[20:0]` | Endereço-base calculado a partir de `hash_index`. |
| `word_index[2:0]` | Índice da palavra solicitada, de 0 a 4. |

### 1.3. Interface do módulo

| Sinal | Direção | Largura | Descrição |
|---|---|---:|---|
| `clk` | Entrada | 1 bit | Clock; operações sequenciais ocorrem na borda de subida. |
| `reset` | Entrada | 1 bit | Reset síncrono, ativo em nível alto. |
| `hash_index` | Entrada | 16 bits | Índice da entrada a consultar na Flow Table. |
| `flow_key` | Entrada | 104 bits | Chave do fluxo; conectada, mas ainda não utilizada nesta etapa. |
| `packet_length` | Entrada | 16 bits | Comprimento do pacote; conectado, mas ainda não utilizado. |
| `timestamp` | Entrada | 80 bits | Timestamp do pacote; conectado, mas ainda não utilizado. |
| `hash_valid` | Entrada | 1 bit | Indica que o índice recebido é válido. |
| `rd_en` | Saída | 1 bit | Solicita uma leitura à Flow Table. |
| `rd_addr` | Saída | 21 bits | Endereço da palavra solicitada. |
| `rd_data` | Entrada | 32 bits | Palavra retornada pela memória. |
| `rd_valid` | Entrada | 1 bit | Indica que `rd_data` contém uma resposta válida. |
| `flow_entry` | Saída | 384 bits | Armazena os dados recebidos durante o LOOKUP. |

### 1.4. Funcionamento da FSM

O Controller utiliza quatro estados:

| Estado | Funcionamento | Próximo estado |
|---|---|---|
| `IDLE` | Aguarda `hash_valid`. Quando recebe um índice válido, calcula `base_addr` e limpa `flow_entry`. | `LOOKUP_REQ`, quando `hash_valid = 1`. |
| `LOOKUP_REQ` | Ativa `rd_en` e apresenta `base_addr + word_index` em `rd_addr`. | `LOOKUP_WAIT`. |
| `LOOKUP_WAIT` | Aguarda `rd_valid`. Quando recebe uma resposta válida, armazena `rd_data` na posição correspondente de `flow_entry`. | `LOOKUP_REQ` para as palavras seguintes ou `LOOKUP_DONE` após W4. |
| `LOOKUP_DONE` | Indica internamente que as cinco palavras foram recebidas. | `IDLE`. |

O bloco combinacional `always_comb` define os valores de `rd_en` e `rd_addr`. Os valores padrão são zero, evitando a inferência de latches. Somente em `LOOKUP_REQ` uma leitura é solicitada.

O bloco sequencial `always_ff` implementa a FSM, atualiza `base_addr` e armazena os dados recebidos. O reset é síncrono e ativo em nível alto.

### 1.5. Armazenamento das palavras

Cada palavra recebida é armazenada usando seleção variável de bits:

```systemverilog
flow_entry[word_index * 32 +: 32] <= rd_data;
```

O mapeamento utilizado é:

| Palavra | Bits de `flow_entry` |
|---|---|
| W0 | `[31:0]` |
| W1 | `[63:32]` |
| W2 | `[95:64]` |
| W3 | `[127:96]` |
| W4 | `[159:128]` |
| Não utilizados nesta etapa | `[383:160]` |

O sinal `flow_entry` possui 384 bits, conforme a interface atual. Portanto, somente os 160 bits inferiores são preenchidos pelas cinco leituras. Os bits `[383:160]` permanecem zerados porque o registro é limpo quando um novo lookup é aceito.

O avanço da FSM depende de `rd_valid`, e não de uma quantidade fixa de ciclos. Assim, o Controller aguarda a resposta da memória antes de avançar para a próxima palavra.

---

## 2. `tb_controller.sv` — Testbench

### Objetivo

O testbench verifica o comportamento da etapa de LOOKUP por meio de uma memória comportamental simplificada.

São verificados os seguintes requisitos:

- O endereço-base corresponde a `hash_index × 16`.
- Cada lookup gera exatamente cinco solicitações de leitura.
- Os endereços solicitados são consecutivos e estão na ordem correta.
- As palavras retornadas são armazenadas nas posições esperadas de `flow_entry`.
- Os bits `[383:160]` permanecem zerados.

### 2.1. Configuração e conexão

O testbench declara os sinais de entrada e saída, instancia o Controller como `dut` e conecta as portas pelos nomes dos sinais.

A memória de teste é declarada como:

```systemverilog
logic [31:0] memory [0:4095];
```

Ela contém 4.096 palavras de 32 bits e é inicializada com zero no início da simulação.

Essa memória é apenas um modelo reduzido para os testes. Ela não representa a capacidade total prevista para a Flow Table.

### 2.2. Clock

O clock é gerado por:

```systemverilog
initial clk = 1'b0;
always #5 clk = ~clk;
```

O sinal é invertido a cada 5 ns, resultando em um período de 10 ns, equivalente a uma frequência de 100 MHz.

### 2.3. Modelo comportamental da memória

O modelo utiliza os sinais `pending_read` e `pending_addr` para representar uma solicitação pendente.

Quando `rd_en` é amostrado na borda de subida, o modelo registra o endereço solicitado. Na borda seguinte, atualiza `rd_data` e `rd_valid` para indicar a resposta da memória.

Como os blocos sequenciais são executados na mesma borda de clock, o Controller consome a resposta na borda seguinte àquela em que o modelo atualiza `rd_data` e `rd_valid`.

Esse comportamento permite verificar se a FSM aguarda corretamente a resposta antes de solicitar a próxima palavra.

### 2.4. Monitor de endereços

O monitor observa cada borda de subida em que `rd_en = 1`.

Para cada solicitação, compara o endereço emitido com:

```systemverilog
expected_base + reads_seen
```

Se houver divergência, o testbench registra um erro com `$error` e incrementa `errors`. O contador `reads_seen` é incrementado a cada solicitação observada.

Dessa forma, são verificados tanto os endereços quanto a quantidade e a ordem das leituras.

### 2.5. Tarefa `run_lookup(test_hash)`

A tarefa executa um cenário de teste completo.

1. Aguarda o Controller retornar ao estado `IDLE`.
2. Calcula o endereço-base esperado a partir de `test_hash`.
3. Zera `reads_seen`.
4. Grava cinco valores de teste na memória, a partir do endereço-base.
5. Aplica `hash_index`, `flow_key`, `packet_length` e `timestamp`, ativando `hash_valid` por um ciclo.
6. Aguarda o estado `LOOKUP_DONE`.
7. Confere as cinco palavras armazenadas em `flow_entry`.
8. Verifica se os bits `[383:160]` permanecem zerados.
9. Confirma que foram emitidas exatamente cinco solicitações.

Os valores utilizados para as palavras são:

```systemverilog
memory[base + j] = 32'hA0000000 + j;
```

Assim, W0 contém `A0000000`, W1 contém `A0000001`, e assim sucessivamente até W4, que contém `A0000004`.

Como cada palavra tem um valor distinto, o teste detecta dados incorretos ou armazenados na posição errada.

Os metadados adicionais são mantidos constantes durante os três cenários:

- `flow_key = 0x123456789ABCDEF123456789AB`
- `packet_length = 128`
- `timestamp = 1234`

Esses valores verificam a conexão dos sinais, mas não sua utilização funcional, pois ainda não participam da lógica de lookup.

### 2.6. Sequência de testes

Após manter `reset = 1` por três bordas de descida, o testbench libera o reset e executa os seguintes cenários:

| Teste | `hash_index` | Base esperada | Endereços de leitura |
|---|---:|---:|---|
| 1 | 0 | 0 (`0x000`) | 0, 1, 2, 3, 4 |
| 2 | 5 | 80 (`0x050`) | 80, 81, 82, 83, 84 |
| 3 | 100 (`0x64`) | 1600 (`0x640`) | 1600, 1601, 1602, 1603, 1604 |

Os cenários cobrem o índice zero, um índice pequeno e um índice maior, verificando o cálculo do endereço-base e a sequência de endereços.

Ao final, o testbench imprime `TODOS OS TESTES PASSARAM!` quando `errors == 0`. Caso contrário, informa a quantidade de erros. Um timeout global de 100 µs encerra a simulação com `$fatal` se o teste não terminar.

---

## 3. Análise da forma de onda

### 3.1. Sinais relevantes

Durante a simulação, os sinais de maior interesse são:

- `hash_valid` e `hash_index`: identificam a entrada solicitada.
- `state`: mostra a evolução da FSM.
- `rd_en` e `rd_addr`: indicam as solicitações de leitura.
- `pending_read` e `pending_addr`: mostram a solicitação registrada pelo modelo de memória.
- `rd_valid` e `rd_data`: indicam a resposta da memória.
- `flow_entry`: mostra as palavras armazenadas pelo Controller.
- `reads_seen` e `errors`: auxiliam na verificação do testbench.

### 3.2. Sequência de um lookup

Para o primeiro teste, com `hash_index = 0`, o endereço-base é zero.

Considerando a execução descrita pelo RTL e pelo modelo de memória, a sequência típica é:

| Instante aproximado | Evento |
|---|---|
| 30 ns | O reset é liberado. |
| 40 ns | `hash_valid` é ativado junto aos metadados, antes da borda de subida seguinte. |
| 45 ns | O Controller aceita o índice, registra o endereço-base e entra em `LOOKUP_REQ`. |
| 45–55 ns | `rd_en` fica ativo para a leitura de W0, no endereço 0. |
| 55 ns | A memória registra a solicitação; o Controller passa a aguardar a resposta. |
| 65 ns | O modelo de memória atualiza `rd_data` e `rd_valid`. |
| 75 ns | O Controller consome a resposta e armazena W0 em `flow_entry[31:0]`. |
| 75, 105, 135 e 165 ns | Início das solicitações seguintes, para W1 a W4. |
| 195 ns | O Controller consome W4 e entra em `LOOKUP_DONE`. |
| 205 ns | O Controller retorna a `IDLE`. |

Os instantes são referentes à sequência de simulação descrita e devem ser conferidos na forma de onda gerada pelo simulador.

### 3.3. O que verificar na forma de onda

![Forma de onda – sinais do Controller e do modelo de memória](imagens/waveform_1.png)

**Entrada do pacote:** `hash_valid` deve ser aceito quando o Controller estiver em `IDLE`. Os valores de `hash_index` dos três testes são `0x0000`, `0x0005` e `0x0064`.

**Solicitações de leitura:** cada lookup deve gerar cinco pulsos de `rd_en`, um para cada palavra W0–W4. Com o modelo atual, as solicitações começam aproximadamente a cada 30 ns.

**Endereços:** `rd_addr` deve percorrer cinco endereços consecutivos a partir da base calculada. Para os três testes, as sequências terminam nos endereços 4, 84 e 1604, respectivamente.

**Respostas da memória:** `rd_valid` deve indicar cada resposta, e `rd_data` deve conter os valores de teste correspondentes.

**Armazenamento:** `flow_entry[31:0]` recebe W0, `flow_entry[63:32]` recebe W1, e assim sucessivamente até W4 em `flow_entry[159:128]`.

**Verificação:** `reads_seen` deve chegar a 5 em cada cenário, e `errors` deve permanecer em zero se todas as verificações forem aprovadas.

---

## 4. Critérios de verificação

| Requisito | Evidência esperada |
|---|---|
| Instanciar o Controller | Portas conectadas corretamente entre `tb_controller` e `dut`. |
| Receber um índice válido | `hash_valid` é aceito quando o Controller está em `IDLE`. |
| Calcular o endereço-base | `base_addr = hash_index × 16`. |
| Gerar os endereços de leitura | Cinco endereços consecutivos, de `base_addr` até `base_addr + 4`. |
| Respeitar a resposta da memória | A FSM aguarda `rd_valid` antes de avançar para a próxima palavra. |
| Emitir cinco solicitações | `reads_seen == 5` em cada teste. |
| Armazenar as palavras corretamente | W0–W4 coincidem com `A0000000` a `A0000004`. |
| Manter os bits restantes zerados | `flow_entry[383:160] == 0`. |
| Finalizar a verificação | `errors == 0` e mensagem de aprovação no console. |

A aprovação desses critérios valida o comportamento da etapa de lookup nos cenários testados. Ela não comprova o funcionamento das etapas de comparação de chave, atualização de fluxo ou escrita na memória.

---

## 5. Limitações e próximos passos

A implementação atual é uma primeira etapa funcional do Controller, limitada à solicitação e ao armazenamento de cinco palavras.

As principais limitações são:

- **Metadados:** `flow_key`, `packet_length` e `timestamp` estão conectados, mas ainda não são utilizados. A lógica atual registra o endereço-base derivado de `hash_index`, sem registrar separadamente os demais metadados.
- **Handshake:** não existe um sinal `in_ready`. Um `hash_valid` apresentado enquanto o Controller está ocupado não é aceito. O testbench evita esse caso aguardando o retorno a `IDLE`.
- **Leitura parcial:** somente W0–W4 são lidas. As palavras restantes da entrada não são carregadas em `flow_entry`.
- **Largura de endereço:** `rd_addr` possui 21 bits, enquanto os endereços válidos da memória prevista cabem em 20 bits. A largura deverá ser alinhada durante a integração com a Flow Table.
- **Modelo de memória:** o testbench utiliza uma memória comportamental de 4096 palavras, suficiente para os cenários escolhidos, mas menor que a capacidade prevista para a Flow Table.
- **Tratamento de fluxos:** ainda não há comparação de `flow_key`, classificação HIT/MISS/COLLISION ou descarte de colisões.
- **Escrita:** os sinais `wr_en`, `wr_addr`, `wr_data` e `wr_done` não fazem parte da interface implementada nesta etapa.
- **Finalização:** a interface com o Flow Finalizer ainda não está implementada.

Como próximos passos, podem ser adicionados o armazenamento dos metadados recebidos, a comparação da chave do fluxo e as decisões de HIT/MISS/COLLISION. Em seguida, podem ser desenvolvidas as operações de escrita na Flow Table e a integração com o Flow Finalizer.
