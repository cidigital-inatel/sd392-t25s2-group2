# Validação do Packet Parser — Campanha Ethernet II P01–P14

## 1\. Objetivo

Esta campanha teve como objetivo validar o `packet\_parser` utilizando um arquivo PCAP com **quadros Ethernet II reais**, permitindo testar o caminho completo:

```text
Ethernet II
   ↓
EtherType
   ↓
IPv4
   ↓
TCP/UDP
   ↓
Metadados
```

Diferentemente da campanha anterior, baseada em captura de loopback/`DLT\_NULL`, este PCAP possui cabeçalho Ethernet II de 14 bytes e permite validar também o campo `EtherType`.

\---

## 2\. Arquivos utilizados

```text
packet\_parser.sv
tb\_packet\_parser\_P01\_P14\_ethernet.sv
trafego\_referencia\_P01\_P14.pcap
trafego\_referencia\_esperado.json
```

O arquivo de referência define:

* PCAP clássico em little-endian;
* quadros Ethernet II;
* timestamps em microssegundos no arquivo PCAP;
* contrato de timestamp do Parser como valor escalar de 80 bits em nanossegundos;
* resultados esperados para os pacotes P01 a P14.

\---

## 3\. Configuração do Parser

Para esta campanha foi utilizado:

```systemverilog
.L3\_OFFSET(14)
```

Isso corresponde ao formato Ethernet II:

```text
Dst MAC     = 6 bytes
Src MAC     = 6 bytes
EtherType   = 2 bytes
IPv4        = inicia no byte 14
```

Para pacotes IPv4, o EtherType esperado é:

```text
0x0800
```

\---

## 4\. Organização da interface

### TDATA

A organização de bytes segue o padrão utilizado pela frente de verificação:

```text
byte 0 → TDATA\[7:0]
byte 1 → TDATA\[15:8]
...
byte 7 → TDATA\[63:56]
```

### TKEEP

```text
1 byte válido  → 8'h01
2 bytes válidos → 8'h03
3 bytes válidos → 8'h07
4 bytes válidos → 8'h0F
5 bytes válidos → 8'h1F
6 bytes válidos → 8'h3F
7 bytes válidos → 8'h7F
8 bytes válidos → 8'hFF
```

### Timestamp

Nesta campanha:

```text
timestamp\[79:0] = valor escalar em nanossegundos
```

Exemplo:

```text
P01 → 1000000000 ns
P02 → 1000100000 ns
P07 → 3000900000 ns
```

\---

## 5\. Casos de teste

|Pacote|Cenário|Resultado esperado|
|-|-|-|
|P01|TCP F1 — início|`valid=1`|
|P02|TCP F1 — segundo pacote|`valid=1`|
|P03|TCP F1 — terceiro pacote|`valid=1`|
|P04|UDP F2 — início|`valid=1`|
|P05|UDP F2 — segundo pacote|`valid=1`|
|P06|TCP F3 — IHL=6|`valid=1`|
|P07|TCP F3 — IHL=15|`valid=1`|
|P08|UDP F4 — pacote único|`valid=1`|
|P09|Protocolo IPv4 não suportado|`valid=0`|
|P10|EtherType não IPv4|`valid=0`|
|P11|IPv4 fragmentado (`MF=1`)|`valid=0`|
|P12|`TUSER=0` no `TLAST`|`valid=0`|
|P13|IHL=4 inválido|`valid=0`|
|P14|Quadro truncado / `TLAST` antecipado|`valid=0`|

\---

## 6\. Metadados esperados dos pacotes válidos

### P01

```text
src\_ip        = 192.168.1.10
dst\_ip        = 8.8.8.8
src\_port      = 52100
dst\_port      = 443
protocol      = 6
packet\_length = 40
timestamp     = 1000000000 ns
```

### P02

```text
src\_ip        = 192.168.1.10
dst\_ip        = 8.8.8.8
src\_port      = 52100
dst\_port      = 443
protocol      = 6
packet\_length = 60
timestamp     = 1000100000 ns
```

### P03

```text
src\_ip        = 192.168.1.10
dst\_ip        = 8.8.8.8
src\_port      = 52100
dst\_port      = 443
protocol      = 6
packet\_length = 52
timestamp     = 1000500000 ns
```

### P04

```text
src\_ip        = 192.168.1.20
dst\_ip        = 8.8.4.4
src\_port      = 40000
dst\_port      = 53
protocol      = 17
packet\_length = 28
timestamp     = 2000000000 ns
```

### P05

```text
src\_ip        = 192.168.1.20
dst\_ip        = 8.8.4.4
src\_port      = 40000
dst\_port      = 53
protocol      = 17
packet\_length = 36
timestamp     = 2000200000 ns
```

### P06

```text
src\_ip        = 10.0.0.1
dst\_ip        = 10.0.0.2
src\_port      = 12345
dst\_port      = 80
protocol      = 6
packet\_length = 44
timestamp     = 3000000000 ns
```

### P07

```text
src\_ip        = 10.0.0.1
dst\_ip        = 10.0.0.2
src\_port      = 12345
dst\_port      = 80
protocol      = 6
packet\_length = 80
timestamp     = 3000900000 ns
```

### P08

```text
src\_ip        = 172.16.0.10
dst\_ip        = 172.16.0.20
src\_port      = 5000
dst\_port      = 5001
protocol      = 17
packet\_length = 28
timestamp     = 4000000000 ns
```

\---

## 7\. Resultado da simulação

O ModelSim apresentou:

```text
# ---- P 1 incl\_len=54 orig\_len=54 ts\_ns=1000000000 ----
# PASS P 1: src=c0a8010a dst=08080808 sport=52100 dport=443 proto=6 len=40 ts=1000000000
# ---- P 2 incl\_len=74 orig\_len=74 ts\_ns=1000100000 ----
# PASS P 2: src=c0a8010a dst=08080808 sport=52100 dport=443 proto=6 len=60 ts=1000100000
# ---- P 3 incl\_len=66 orig\_len=66 ts\_ns=1000500000 ----
# PASS P 3: src=c0a8010a dst=08080808 sport=52100 dport=443 proto=6 len=52 ts=1000500000
# ---- P 4 incl\_len=42 orig\_len=42 ts\_ns=2000000000 ----
# PASS P 4: src=c0a80114 dst=08080404 sport=40000 dport=53 proto=17 len=28 ts=2000000000
# ---- P 5 incl\_len=50 orig\_len=50 ts\_ns=2000200000 ----
# PASS P 5: src=c0a80114 dst=08080404 sport=40000 dport=53 proto=17 len=36 ts=2000200000
# ---- P 6 incl\_len=58 orig\_len=58 ts\_ns=3000000000 ----
# PASS P 6: src=0a000001 dst=0a000002 sport=12345 dport=80 proto=6 len=44 ts=3000000000
# ---- P 7 incl\_len=94 orig\_len=94 ts\_ns=3000900000 ----
# PASS P 7: src=0a000001 dst=0a000002 sport=12345 dport=80 proto=6 len=80 ts=3000900000
# ---- P 8 incl\_len=42 orig\_len=42 ts\_ns=4000000000 ----
# PASS P 8: src=ac10000a dst=ac100014 sport=5000 dport=5001 proto=17 len=28 ts=4000000000
```

Os pacotes P09 a P14 não geraram `valid`, conforme esperado.

Resultado final:

```text
==============================================
PASS: campanha Ethernet II P01-P14 concluida.
8 pacotes aceitos e 6 descartados.
==============================================
---

## 8\. Comportamento da FSM

Durante a recepção dos pacotes válidos, foram observadas transições compatíveis com o fluxo:

```text
IDLE
  ↓
ETHERNET
  ↓
IPV4
  ↓
WAIT\_L4
  ↓
SELECT\_TRANSP
  ↓
TCP\_STATE / UDP\_STATE
  ↓
WAIT\_LAST
  ↓
IDLE
```

A finalização ocorre diretamente no `TLAST`, permitindo que o Parser retorne a `IDLE` e fique disponível para receber o próximo pacote sem estados adicionais de pós-processamento.

\---

## 9\. Validações realizadas

|Item|Status|
|-|-|
|Ethernet II — 14 bytes|PASS|
|EtherType IPv4 (`0x0800`)|PASS|
|Descarte de EtherType não IPv4|PASS|
|IPv4|PASS|
|TCP|PASS|
|UDP|PASS|
|IHL=5|PASS|
|IHL=6|PASS|
|IHL=15|PASS|
|IHL inválido|PASS|
|Protocolo IPv4 não suportado|PASS|
|Fragmentação IPv4|PASS|
|`TUSER=0`|PASS|
|Quadro truncado|PASS|
|Extração de `src\_ip`|PASS|
|Extração de `dst\_ip`|PASS|
|Extração de `src\_port`|PASS|
|Extração de `dst\_port`|PASS|
|Extração de `protocol`|PASS|
|Extração de `packet\_length`|PASS|
|Timestamp|PASS|
|8 pacotes válidos aceitos|PASS|
|6 pacotes inválidos descartados|PASS|
|Erros na campanha|0|

\---

## 10\. Conclusão

A campanha P01–P14 validou com sucesso o funcionamento do `packet\_parser` utilizando um PCAP contendo quadros Ethernet II reais.

Ao contrário da campanha anterior com captura de loopback/`DLT\_NULL`, foi possível validar nesta etapa o processamento completo do cabeçalho Ethernet, incluindo o reconhecimento do `EtherType`.

Os oito pacotes válidos produziram exatamente os metadados esperados, enquanto os seis casos inválidos ou fora de escopo foram corretamente descartados.

O resultado consolidado da campanha foi:

```text
Campanha Ethernet II P01–P14: PASS
Pacotes válidos aceitos:      8/8
Pacotes inválidos descartados: 6/6
Erros:                         0
```

Com isso, fica validado o caminho:

```text
PCAP Ethernet II
      ↓
Interface de 64 bits
      ↓
Packet Parser
      ↓
Metadados IPv4/TCP/UDP
```

