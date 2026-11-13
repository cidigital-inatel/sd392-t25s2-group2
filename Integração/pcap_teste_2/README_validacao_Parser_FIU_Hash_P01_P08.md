# Validação Integrada — Packet Parser + FIU + Hash

## 1. Objetivo

Validar a integração funcional entre os três módulos responsáveis pela extração e identificação inicial dos fluxos:

```text
PCAP
  ↓
Packet Parser
  ↓
Flow Identification Unit (FIU)
  ↓
Hash Unit
```

A campanha utilizou os casos **P01 a P08** do arquivo de referência Ethernet II, todos válidos, com o objetivo de verificar:

- extração correta dos metadados pelo Packet Parser;
- montagem correta da `flow_key` pela FIU;
- propagação correta de `packet_length` e `timestamp`;
- cálculo correto do `hash_index`;
- preservação da mesma `flow_key` e do mesmo hash para pacotes pertencentes à mesma uniflow.

Esta primeira campanha foi executada com intervalo entre os pacotes para validar primeiro a correção funcional da integração, sem misturar o teste com a limitação de throughput da Hash Unit.

---

## 2. Arquivos utilizados

Principais arquivos RTL:

```text
packet_parser.sv
flow_identification_unit.sv
hash_unit.sv
parser_fiu_hash_top.sv
```

Testbench:

```text
tb_parser_fiu_hash.sv
```

Arquivo de entrada:

```text
trafego_referencia_P01_P14.pcap
```

Nesta campanha foram utilizados apenas os casos:

```text
P01 a P08
```

---

## 3. Arquitetura testada

O módulo `parser_fiu_hash_top.sv` foi utilizado como módulo de integração entre os três blocos:

```text
Packet Parser
   │
   │ src_ip
   │ dst_ip
   │ src_port
   │ dst_port
   │ protocol
   │ packet_length
   │ timestamp
   │ valid
   ↓
Flow Identification Unit
   │
   │ flow_key[103:0]
   │ packet_length[15:0]
   │ timestamp[79:0]
   │ valid
   ↓
Hash Unit
   │
   ├── hash_index[15:0]
   ├── flow_key[103:0]
   ├── packet_length[15:0]
   ├── timestamp[79:0]
   └── hash_valid
```

O `parser_fiu_hash_top.sv` não altera os dados. Sua função é apenas instanciar e conectar os três módulos.

---

## 4. Interface do Packet Parser

A entrada do Parser utiliza:

```text
TDATA[63:0]
TKEEP[7:0]
TVALID
TLAST
TUSER
timestamp_in[79:0]
```

Convenção de bytes:

```text
primeiro byte  → TDATA[7:0]
segundo byte   → TDATA[15:8]
...
oitavo byte    → TDATA[63:56]
```

O teste utilizou:

```text
L3_OFFSET = 14
```

pois o arquivo de referência utiliza **Ethernet II**.

---

## 5. Timestamp

Para esta campanha integrada foi utilizado o formato definido para a Semana 8:

```text
timestamp[79:32] = segundos       (48 bits)
timestamp[31:0]  = nanossegundos (32 bits)
```

O PCAP possui timestamp em segundos e microssegundos.

A testbench realiza a conversão:

```text
nanoseconds = microseconds × 1000
```

O Packet Parser apenas captura e repassa o campo de 80 bits, sem interpretar seu conteúdo.

---

## 6. Casos utilizados

### P01 — TCP / Fluxo F1

```text
src_ip        = 192.168.1.10
dst_ip        = 8.8.8.8
src_port      = 52100
dst_port      = 443
protocol      = 6
packet_length = 40
timestamp     = 1 s + 0 ns
hash_index    = 40984
```

### P02 — TCP / Fluxo F1

```text
src_ip        = 192.168.1.10
dst_ip        = 8.8.8.8
src_port      = 52100
dst_port      = 443
protocol      = 6
packet_length = 60
timestamp     = 1 s + 100000 ns
hash_index    = 40984
```

### P03 — TCP / Fluxo F1

```text
src_ip        = 192.168.1.10
dst_ip        = 8.8.8.8
src_port      = 52100
dst_port      = 443
protocol      = 6
packet_length = 52
timestamp     = 1 s + 500000 ns
hash_index    = 40984
```

### P04 — UDP / Fluxo F2

```text
src_ip        = 192.168.1.20
dst_ip        = 8.8.4.4
src_port      = 40000
dst_port      = 53
protocol      = 17
packet_length = 28
timestamp     = 2 s + 0 ns
hash_index    = 12848
```

### P05 — UDP / Fluxo F2

```text
src_ip        = 192.168.1.20
dst_ip        = 8.8.4.4
src_port      = 40000
dst_port      = 53
protocol      = 17
packet_length = 36
timestamp     = 2 s + 200000 ns
hash_index    = 12848
```

### P06 — TCP / Fluxo F3

```text
src_ip        = 10.0.0.1
dst_ip        = 10.0.0.2
src_port      = 12345
dst_port      = 80
protocol      = 6
packet_length = 44
timestamp     = 3 s + 0 ns
hash_index    = 7940
```

### P07 — TCP / Fluxo F3

```text
src_ip        = 10.0.0.1
dst_ip        = 10.0.0.2
src_port      = 12345
dst_port      = 80
protocol      = 6
packet_length = 80
timestamp     = 3 s + 900000 ns
hash_index    = 7940
```

### P08 — UDP / Fluxo F4

```text
src_ip        = 172.16.0.10
dst_ip        = 172.16.0.20
src_port      = 5000
dst_port      = 5001
protocol      = 17
packet_length = 28
timestamp     = 4 s + 0 ns
hash_index    = 39485
```

---

## 7. Fluxos esperados

Os oito pacotes pertencem a quatro uniflows:

| Fluxo | Pacotes | Protocolo | Hash esperado |
|---|---|---|---:|
| F1 | P01, P02, P03 | TCP | 40984 |
| F2 | P04, P05 | UDP | 12848 |
| F3 | P06, P07 | TCP | 7940 |
| F4 | P08 | UDP | 39485 |

A `flow_key` é definida como:

```text
flow_key = {
    src_ip,
    dst_ip,
    src_port,
    dst_port,
    protocol
}
```

Total:

```text
32 + 32 + 16 + 16 + 8 = 104 bits
```

---

## 8. Resultado da simulação

Resultado observado no ModelSim:

```text
---- ENVIA P 1 len=54 sec=1 ns=0 ----
PASS HASH #1: hash=40984 key=c0a8010a08080808cb8401bb06 len=40

---- ENVIA P 2 len=74 sec=1 ns=100000 ----
PASS HASH #2: hash=40984 key=c0a8010a08080808cb8401bb06 len=60

---- ENVIA P 3 len=66 sec=1 ns=500000 ----
PASS HASH #3: hash=40984 key=c0a8010a08080808cb8401bb06 len=52

---- ENVIA P 4 len=42 sec=2 ns=0 ----
PASS HASH #4: hash=12848 key=c0a80114080804049c40003511 len=28

---- ENVIA P 5 len=50 sec=2 ns=200000 ----
PASS HASH #5: hash=12848 key=c0a80114080804049c40003511 len=36

---- ENVIA P 6 len=58 sec=3 ns=0 ----
PASS HASH #6: hash=7940 key=0a0000010a0000023039005006 len=44

---- ENVIA P 7 len=94 sec=3 ns=900000 ----
PASS HASH #7: hash=7940 key=0a0000010a0000023039005006 len=80

---- ENVIA P 8 len=42 sec=4 ns=0 ----
PASS HASH #8: hash=39485 key=ac10000aac1000141388138911 len=28
```

Resumo final:

```text
======================================================
PASS: Parser -> FIU -> Hash.
8/8 pacotes processados corretamente.
Hashes F1=40984 F2=12848 F3=7940 F4=39485.
======================================================
```

---

## 9. Verificações realizadas

A campanha confirmou:

| Verificação | Resultado |
|---|---|
| Parser extraiu os metadados corretos | PASS |
| FIU montou corretamente a `flow_key` de 104 bits | PASS |
| Pacotes do mesmo fluxo produziram a mesma `flow_key` | PASS |
| Pacotes do mesmo fluxo produziram o mesmo `hash_index` | PASS |
| `packet_length` propagado corretamente | PASS |
| `timestamp` propagado corretamente | PASS |
| TCP e UDP processados corretamente | PASS |
| IPv4 com diferentes tamanhos de cabeçalho presentes nos casos de referência | PASS |
| P01–P08 processados | 8/8 |

---

## 10. Observação sobre throughput

Nesta primeira campanha foi utilizada uma folga deliberada de:

```text
20 clocks entre os quadros
```

O objetivo foi validar primeiro a correção funcional da integração.

Posteriormente foi executado um teste específico removendo essa folga.

Nesse teste, a Hash Unit recebeu uma nova transferência enquanto ainda estava ocupada e gerou:

```text
PROTOCOL_VIOLATION:
HASH recebeu nova transferencia ocupado;
intervalo minimo de 16 clocks.
```

Portanto, os resultados devem ser interpretados separadamente:

```text
Correção funcional Parser → FIU → Hash: VALIDADA.

Operação com pacotes consecutivos sem espaçamento:
LIMITADA PELO THROUGHPUT DA HASH UNIT.
```

---

## 11. Conclusão

A integração entre **Packet Parser, Flow Identification Unit e Hash Unit** foi validada com sucesso utilizando os casos P01 a P08 do PCAP Ethernet II de referência.

Todos os oito pacotes válidos produziram os metadados, `flow_key` e `hash_index` esperados.

Também foi confirmado que pacotes pertencentes à mesma uniflow produzem a mesma chave e o mesmo índice de hash, enquanto `packet_length` e `timestamp` permanecem associados individualmente a cada pacote.

Resultado final:

```text
8/8 pacotes processados corretamente
4/4 fluxos identificados corretamente
4/4 hashes esperados confirmados
0 erros funcionais
```

A campanha valida funcionalmente o caminho:

```text
Packet Parser → FIU → Hash
```

O comportamento de throughput foi tratado posteriormente em campanha específica.
