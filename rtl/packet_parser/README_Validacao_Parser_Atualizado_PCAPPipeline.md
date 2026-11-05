# Validação Funcional do Packet Parser — Estado Atual

## 1. Objetivo

Este documento consolida o estado atual da validação funcional do **Packet Parser** e registra a baseline que será utilizada na próxima etapa de integração com a frente de verificação.

A versão atual do Parser utiliza:

```text
reset síncrono, ativo em nível alto
valid como sinal de saída dos metadados
timestamp de 80 bits em nanossegundos
TDATA de 64 bits
TKEEP de 8 bits
TVALID
TLAST
TUSER
```

A interface de saída padronizada é:

```text
src_ip[31:0]
dst_ip[31:0]
src_port[15:0]
dst_port[15:0]
protocol[7:0]
packet_length[15:0]
timestamp[79:0]
valid
```

---

## 2. Alteração da FSM para tráfego contínuo

Durante a primeira execução da Campanha 3 foi identificado que a versão anterior da FSM não suportava quadros consecutivos sem ciclos ociosos.

A sequência anterior era:

```text
TLAST
  ↓
CHECK_FRAME
  ↓
OUTPUT_STATE
  ↓
IDLE
```

Como a interface de entrada não possui `TREADY`, o quadro seguinte poderia começar enquanto o Parser ainda estava em `CHECK_FRAME` ou `OUTPUT_STATE`, resultando em perda de beats.

Na primeira execução da Campanha 3 foram enviados cinco quadros consecutivos, porém apenas dois pulsos de `valid` foram produzidos.

A FSM foi então modificada para realizar a finalização diretamente no ciclo de `TLAST`:

```text
TVALID = 1
TLAST  = 1
      ↓
verificação de validade do quadro
      ↓
valid = 1 ou 0
      ↓
state <= IDLE
```

Com isso, no ciclo seguinte a FSM já está pronta para receber o primeiro beat do próximo quadro.

Os estados `CHECK_FRAME` e `OUTPUT_STATE` deixaram de fazer parte do caminho de finalização entre quadros.

---

## 3. Campanha 1 — Tráfego válido P01–P08

Foram validados:

- IPv4 + TCP;
- IPv4 + UDP;
- pacotes pertencentes ao mesmo fluxo;
- fluxos distintos;
- diferentes tamanhos;
- diferentes timestamps;
- `IHL = 5`;
- `IHL > 5`;
- `IHL = 15`;
- último beat parcial com `TKEEP`.

Resultado:

```text
PASS P01
PASS P02
PASS P03
PASS P04
PASS P05
PASS P06
PASS P07
PASS P08
PASS: trafego de referencia P01-P08 validado.
```

**CAMPANHA 1 = PASS**

---

## 4. Campanha 2 — Pacotes fora do escopo e inválidos

Foram testados:

```text
P09 — protocolo IPv4 não suportado
P10 — EtherType diferente de IPv4
P11 — IPv4 fragmentado
P12 — quadro inválido por TUSER
P13 — IHL < 5
P14 — quadro truncado
P15 — pacote TCP válido para recuperação
```

Resultado:

```text
PASS P15: recuperacao apos P09-P14.
PASS P09: protocolo nao suportado descartado.
PASS P10: EtherType nao IPv4 descartado.
PASS P11: IPv4 fragmentado descartado.
PASS P12: TUSER=0 descartado.
PASS P13: IHL<5 descartado.
PASS P14: quadro truncado descartado.
PASS: campanha P09-P14 + recuperacao P15 validada.
```

**CAMPANHA 2 = PASS**

A campanha confirmou ainda que somente o P15 produziu `valid = 1`.

---

## 5. Campanha 3 — Tráfego contínuo sem ciclos ociosos

A sequência utilizada foi:

```text
C01 = P01 / F1 / TCP
C02 = P04 / F2 / UDP
C03 = P02 / F1 / TCP
C04 = P05 / F2 / UDP
C05 = P03 / F1 / TCP
```

Após a correção da FSM:

```text
PASS C01
PASS C02
PASS C03
PASS C04
PASS C05
PASS CAMPANHA 3: 5 pacotes consecutivos sem ciclos ociosos.
```

**CAMPANHA 3 = PASS**

---

## 6. Regressão após a correção da FSM

Após a correção introduzida para a Campanha 3, as Campanhas 1 e 2 foram executadas novamente utilizando o mesmo `packet_parser.sv`.

| Campanha | Objetivo | Resultado |
|---|---|---|
| Campanha 1 | Fluxos válidos P01–P08 | **PASS** |
| Campanha 2 | Descartes P09–P14 + recuperação P15 | **PASS** |
| Campanha 3 | Pacotes consecutivos sem ciclos ociosos | **PASS** |

A regressão confirmou que a alteração destinada ao tráfego back-to-back não introduziu falhas nos casos anteriormente validados.

---

## 7. UT-11 — Reset durante o recebimento de um quadro

O UT-11 verificou o comportamento do Parser quando o reset síncrono é aplicado durante o recebimento de um quadro.

Sequência do teste:

```text
início do quadro P1
      ↓
alguns beats recebidos
      ↓
reset = 1
      ↓
próxima borda de clock
      ↓
FSM retorna a IDLE
      ↓
P1 é abandonado
      ↓
novo quadro P2
      ↓
processamento normal
```

Resultado:

```text
PASS UT-11: FSM retornou a IDLE apos reset.
PASS UT-11: pacote de recuperacao processado corretamente.
PASS UT-11: reset durante quadro validado com recuperacao.
```

**UT-11 = PASS**

O quadro interrompido não gerou `valid`, e o quadro seguinte foi processado normalmente.

---

## 8. UT-16 — TKEEP parcial em posição crítica

Foi realizado um teste adicional com `TKEEP` parcial em um beat interno do quadro.

O teste demonstrou que, nessa condição artificial, o Parser ainda poderia liberar `valid`.

Entretanto, esse cenário foi classificado como:

```text
FORA DO ESCOPO DA INTERFACE
```

A convenção adotada para a interface do projeto é:

```text
beats intermediários → TKEEP = FF
último beat           → TKEEP pode ser parcial
```

Portanto, `TKEEP` parcial em um beat interno não é considerado um comportamento esperado da MAC nesta versão do sistema.

O caso relevante ao contrato da interface — `TKEEP` parcial no último beat — já foi validado nas campanhas anteriores.

Assim:

```text
UT-16 = FORA DO ESCOPO DA INTERFACE
```

Não será realizada alteração adicional no RTL para suportar `TKEEP` parcial em beats internos.

---

## 9. Matriz atualizada de testes unitários

| ID | Cenário | Situação | Evidência |
|---|---|---|---|
| UT-01 | IPv4 + TCP válido, `IHL=5` | **PASS** | P01 |
| UT-02 | IPv4 + UDP válido, `IHL=5` | **PASS** | P04 |
| UT-03 | IPv4 com `IHL > 5` | **PASS** | P06 |
| UT-04 | Protocolo IPv4 não suportado | **PASS** | P09 |
| UT-05 | EtherType diferente de `0x0800` | **PASS** | P10 |
| UT-06 | IPv4 fragmentado | **PASS** | P11 |
| UT-07 | `TUSER=0` no final do quadro | **PASS** | P12 |
| UT-08 | Último beat parcial com `TKEEP` | **PASS** | Campanha 1 |
| UT-09 | Dois pacotes válidos consecutivos | **PASS** | Campanha 3 |
| UT-10 | TCP seguido de UDP | **PASS** | Campanha 3 |
| UT-11 | Reset durante o recebimento de um quadro | **PASS** | UT-11 |
| UT-12 | IPv4 com `IHL < 5` | **PASS** | P13 |
| UT-13 | IPv4 com `IHL = 15` | **PASS** | P07 |
| UT-14 | Quadro truncado com `TLAST` antecipado | **PASS** | P14 |
| UT-15 | Pacotes consecutivos sem ciclo ocioso | **PASS** | Campanha 3 |
| UT-16 | `TKEEP` parcial em beat interno | **FORA DO ESCOPO** | contrato da interface |
| UT-17 | Timestamps diferentes em pacotes consecutivos | **PASS** | Campanhas 1 e 3 |

---

## 10. Baseline funcional atual

```text
Ethernet II                PASS
IPv4                       PASS
TCP                        PASS
UDP                        PASS
IHL dinâmico               PASS
IHL máximo                 PASS
fragmentação               PASS / descarte
protocolo não suportado    PASS / descarte
EtherType fora do escopo   PASS / descarte
TUSER inválido             PASS / descarte
quadro truncado            PASS / descarte
TKEEP parcial final        PASS
TKEEP parcial interno      fora do escopo
timestamps 80 bits         PASS
reset síncrono             PASS
valid padronizado          PASS
tráfego back-to-back       PASS
regressão                  PASS
```

Esta versão passa a ser a **baseline funcional atual do Packet Parser**.

---

## 11. Próximo passo — Integração com a frente de verificação

A próxima etapa deixa de utilizar o fluxo intermediário:

```text
PCAP
  ↓
pcap_to_stimulus.py
  ↓
input_stream.txt
  ↓
testbench
  ↓
Packet Parser
```

A frente de verificação desenvolveu um testbench capaz de receber diretamente o conteúdo de um arquivo PCAP e gerar os sinais da interface de entrada do Parser.

O novo fluxo esperado será:

```text
arquivo PCAP
    ↓
testbench da frente de verificação
    ↓
TDATA
TKEEP
TVALID
TLAST
TUSER
timestamp_in
    ↓
Packet Parser
```

O objetivo da integração é eliminar a dependência do arquivo intermediário `input_stream.txt` e aproximar o ambiente de simulação de um fluxo de verificação mais automatizado.

A integração deverá preservar o contrato atual do Parser:

```text
clk
reset
TDATA[63:0]
TKEEP[7:0]
TVALID
TLAST
TUSER
timestamp_in[79:0]
```

e validar as saídas:

```text
src_ip[31:0]
dst_ip[31:0]
src_port[15:0]
dst_port[15:0]
protocol[7:0]
packet_length[15:0]
timestamp[79:0]
valid
```

A primeira integração deverá reutilizar os mesmos PCAPs e cenários já utilizados nas campanhas anteriores, permitindo comparar diretamente os resultados do novo testbench com a baseline já validada.

Critério principal:

```text
mesmo PCAP
+
novo testbench direto
=
mesmos metadados esperados
```

Após essa validação, o fluxo de verificação com PCAP direto poderá substituir o caminho baseado em `input_stream.txt`.
