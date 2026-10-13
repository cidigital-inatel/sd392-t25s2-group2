# Contrato de Interface — Flow Table

Este documento registra exclusivamente o contrato de interface do módulo **Flow Table**, considerando a organização atual da memória com palavras de 32 bits e sua futura utilização em FPGA.

---

## 1. Organização da memória

A Flow Table é organizada como uma memória de palavras de **32 bits**.

| Parâmetro | Valor |
|---|---:|
| Número de entradas de fluxo | 65.536 (`2^16`) |
| Palavras por registro de fluxo | 16 |
| Largura de cada palavra | 32 bits |
| Total de palavras da memória | 1.048.576 (`2^20`) |
| Largura do endereço físico | 20 bits |

Cada registro de fluxo ocupa **16 palavras consecutivas de 32 bits**, totalizando 512 bits por entrada.

O `hash_index` é utilizado pelo Controller para determinar a região de armazenamento correspondente ao registro. A partir dele, o Controller calcula o endereço-base:

```text
base_addr = hash_index × 16
```

Como cada entrada possui 16 palavras, isso também pode ser calculado por:

```text
base_addr = hash_index << 4
```

Os endereços das palavras do registro são então calculados por:

```text
rd_addr / wr_addr = base_addr + word_offset
```

onde `word_offset` varia de `0` a `15`.

---

## 2. Entradas

| Sinal | Largura | Direção | Origem | Descrição |
|---|---:|---|---|---|
| `clk` | 1 bit | Entrada | Sistema | Clock do módulo Flow Table. |
| `rd_en` | 1 bit | Entrada | Controller | Solicita uma operação de leitura. |
| `rd_addr` | 20 bits | Entrada | Controller | Endereço físico da palavra de 32 bits a ser lida. |
| `wr_en` | 1 bit | Entrada | Controller | Solicita uma operação de escrita. |
| `wr_addr` | 20 bits | Entrada | Controller | Endereço físico da palavra de 32 bits a ser escrita. |
| `wr_data` | 32 bits | Entrada | Controller | Dado de 32 bits a ser armazenado na memória. |

---

## 3. Saídas

| Sinal | Largura | Direção | Descrição |
|---|---:|---|---|
| `rd_data` | 32 bits | Saída | Dado de 32 bits lido da memória. |
| `rd_valid` | 1 bit | Saída | Indica que `rd_data` contém um dado válido. |
| `wr_done` | 1 bit | Saída | Indica que a operação de escrita foi concluída. |

---

## 4. Regras de operação

### 4.1 Leitura

A leitura é solicitada quando:

```text
rd_en = 1
```

No ciclo em que `rd_en` está ativo, o Controller fornece o endereço físico da palavra por meio de `rd_addr`.

A Flow Table disponibiliza o dado lido no ciclo seguinte, juntamente com `rd_valid = 1`.

Exemplo:

| Ciclo | Sinal/Operação |
|---|---|
| `N` | `rd_en = 1` e `rd_addr = 80` |
| `N+1` | `rd_valid = 1` e `rd_data = mem[80]` |
| `N+2` | `rd_valid = 0` |

O Controller deve considerar `rd_data` válido somente quando `rd_valid = 1`.

---

### 4.2 Escrita

A escrita é solicitada quando:

```text
wr_en = 1
```

No ciclo da solicitação, o Controller fornece:

```text
wr_addr
wr_data
```

A Flow Table armazena `wr_data` no endereço indicado por `wr_addr`.

A conclusão da operação é indicada por `wr_done`.

Exemplo:

| Ciclo | Sinal/Operação |
|---|---|
| `N` | `wr_en = 1`, `wr_addr = 88`, `wr_data = novo_valor` |
| `N+1` | `wr_done = 1` |

---

## 5. Relação com o Controller

A Flow Table não é responsável por calcular os endereços correspondentes ao `hash_index`.

O **Controller** utiliza o `hash_index` para determinar a região de armazenamento do registro e calcula os endereços físicos das palavras que deverão ser acessadas.

Para um determinado fluxo:

```text
hash_index
     |
     v
base_addr = hash_index × 16
     |
     +---- word 0  -> base_addr + 0
     +---- word 1  -> base_addr + 1
     +---- word 2  -> base_addr + 2
     ...
     +---- word 15 -> base_addr + 15
```

A Flow Table recebe apenas o endereço físico da palavra a ser lida ou escrita.

---

## 6. Resumo da interface

### Entradas

```text
clk
rd_en
rd_addr[19:0]
wr_en
wr_addr[19:0]
wr_data[31:0]
```

### Saídas

```text
rd_data[31:0]
rd_valid
wr_done
```

---

## 7. Exemplo de acesso

### Leitura

Considerando `hash_index = 5`, o endereço-base é `5 × 16 = 80`. Portanto, W0 da entrada 5 está no endereço 80.

```text
Ciclo N:
    rd_en   = 1
    rd_addr = 80    // W0 da entry 5

Ciclo N+1:
    rd_valid = 1
    rd_data  = mem[80]

Ciclo N+2:
    rd_valid = 0
```

### Escrita

Para a mesma entrada, W8 está no endereço `80 + 8 = 88`.

```text
Ciclo N:
    wr_en   = 1
    wr_addr = 88    // W8 da entry 5
    wr_data  = novo valor de 32 bits

Ciclo N+1:
    wr_done = 1
```
