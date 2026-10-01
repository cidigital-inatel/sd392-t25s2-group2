# Contrato de Interface — Packet Parser

Este documento registra exclusivamente o contrato de interface do módulo **Packet Parser**, considerando o estágio atual de simulação e a futura migração para FPGA.

---

## 1. Entradas

| Sinal | Largura | Direção | Origem | Descrição |
|---|---:|---|---|---|
| `clk` | 1 bit | Entrada | Testbench / sistema | Clock do Packet Parser. |
| `reset_n` | 1 bit | Entrada | Testbench / sistema | Reset ativo em nível baixo. |
| `TDATA` | 64 bits | Entrada | MAC RX / testbench | Dados do quadro, até 8 bytes por ciclo. |
| `TKEEP` | 8 bits | Entrada | MAC RX / testbench | Indica quais bytes de `TDATA` são válidos. |
| `TVALID` | 1 bit | Entrada | MAC RX / testbench | Indica que `TDATA` e `TKEEP` são válidos no ciclo atual. |
| `TLAST` | 1 bit | Entrada | MAC RX / testbench | Indica a última transferência do quadro. |
| `TUSER` | 1 bit | Entrada | MAC RX / testbench | Indica a validade final do quadro recebido. |
| `timestamp_in` | A definir | Entrada | PCAP → Python → testbench | Timestamp associado ao pacote durante a fase atual de simulação. |

### Observação sobre o timestamp

Na fase atual, o timestamp será extraído do arquivo **PCAP** pelo ambiente de verificação e fornecido ao Parser como `timestamp_in`.

Quando o projeto migrar para FPGA, a origem desse valor será substituída por um módulo **TSU**.

A lógica interna do Parser deve manter a mesma finalidade: associar um timestamp ao pacote recebido.

---

## 2. Saídas

| Sinal | Largura | Direção | Descrição |
|---|---:|---|---|
| `src_ip` | 32 bits | Saída | Endereço IPv4 de origem. |
| `dst_ip` | 32 bits | Saída | Endereço IPv4 de destino. |
| `src_port` | 16 bits | Saída | Porta de origem TCP ou UDP. |
| `dst_port` | 16 bits | Saída | Porta de destino TCP ou UDP. |
| `protocol` | 8 bits | Saída | Protocolo de transporte indicado pelo cabeçalho IPv4: `6` para TCP e `17` para UDP. |
| `packet_length` | 16 bits *(sugerido)* | Saída | Comprimento do pacote utilizado na atualização de `byte_count`. |
| `timestamp` | Mesma largura de `timestamp_in` | Saída | Timestamp associado ao pacote processado. |
| `metadata_valid` | 1 bit | Saída | Indica que os metadados apresentados na saída correspondem a um quadro válido e podem ser consumidos pelo próximo módulo. |

---

## 3. Regras de validade da interface

| Condição | Contrato |
|---|---|
| Início do quadro | O Parser considera o início de um novo quadro quando está em `IDLE` e `TVALID = 1`. |
| Transferência válida | Como a interface RX adotada não utiliza `TREADY`, toda palavra com `TVALID = 1` deve ser consumida pelo Parser. |
| Fim do quadro | O final do quadro ocorre quando `TVALID && TLAST = 1`. |
| Validade do quadro | Ao final do quadro, `TUSER` determina se os metadados podem ser liberados. Para a interface atualmente adotada: `TUSER = 1` indica quadro válido e `TUSER = 0` indica quadro inválido. |
| Saída válida | `metadata_valid` deve ser ativado somente para pacotes suportados e considerados válidos pelo MAC. |

---

## 4. Definição sugerida para `packet_length`

Sugere-se utilizar como `packet_length` o campo **IPv4 Total Length**, com largura de **16 bits**.

Esse campo informa o tamanho, em bytes, do datagrama IPv4 completo, incluindo:

- cabeçalho IPv4;
- carga útil do IPv4.

Essa escolha é adequada para a primeira PoC porque:

- o campo já está disponível no cabeçalho IPv4;
- não exige contagem adicional dos bytes do quadro no Parser;
- pode ser utilizado diretamente na etapa de Extração de Features:

```text
byte_count = byte_count + packet_length
```

> **Importante:** a equipe deve confirmar essa convenção como contrato global, pois `packet_length` também poderia ser definido como o tamanho total do quadro Ethernet. Uma única definição deve ser utilizada em todos os módulos e também no modelo de referência.

---

## 5. Resumo da interface

### Entradas

```text
clk
reset_n
TDATA[63:0]
TKEEP[7:0]
TVALID
TLAST
TUSER
timestamp_in
```

### Saídas

```text
src_ip[31:0]
dst_ip[31:0]
src_port[15:0]
dst_port[15:0]
protocol[7:0]
packet_length[15:0]   // sugerido
timestamp
metadata_valid
```

### Observação futura

Na implementação em FPGA, `timestamp_in` passará a ser fornecido pelo módulo TSU.
