# Validação Ponta a Ponta — P01 a P08

## 1. Objetivo

Validar a integração funcional completa entre o Packet Parser e os módulos da frente de Features, utilizando os casos válidos P01 a P08 do PCAP de referência.

A cadeia testada foi:

```text
PCAP
  ↓
Packet Parser
  ↓
Flow Identification Unit (FIU)
  ↓
Hash Unit
  ↓
Controller
  ↓
Flow Table
  ↓
Flow Finalizer
  ↓
feature_vector
```

Esta foi a primeira campanha de integração ponta a ponta incluindo o Packet Parser na frente do sistema já integrado de FIU, Hash, Controller, Flow Table e Flow Finalizer.

O objetivo foi verificar se os metadados extraídos pelo Parser percorrem corretamente toda a cadeia e resultam nas features esperadas para os fluxos conhecidos.

---

## 2. Arquivos utilizados

Principais arquivos RTL:

```text
packet_parser.sv
flow_identification_unit.sv
hash_unit.sv
fiu_hash_top.sv
controller_base.sv
flow_table.sv
flow_finalizer.sv
top_extracao_features_entrada.sv
top_parser_extracao_features.sv
```

Testbench:

```text
tb_top_parser_extracao_features.sv
```

Arquivo de entrada:

```text
trafego_referencia_P01_P14.pcap
```

Nesta campanha foram utilizados apenas:

```text
P01 a P08
```

Todos esses casos são pacotes válidos.

---

## 3. Organização dos módulos Top

A integração utiliza dois níveis de módulo `top`.

### 3.1. `top_extracao_features_entrada.sv`

É o top da frente de Features e integra:

```text
FIU
 ↓
Hash
 ↓
Controller
 ↓
Flow Table
 ↓
Flow Finalizer
```

Sua entrada é composta pelos metadados já extraídos:

```text
src_ip
dst_ip
src_port
dst_port
protocol
packet_length
timestamp
in_valid
```

### 3.2. `top_parser_extracao_features.sv`

É o top externo utilizado nesta campanha.

Ele adiciona o Packet Parser antes da frente de Features:

```text
top_parser_extracao_features
│
├── Packet Parser
│
└── top_extracao_features_entrada
     ├── FIU
     ├── Hash
     ├── Controller
     ├── Flow Table
     └── Flow Finalizer
```

Assim, a testbench fornece diretamente o stream de pacotes e observa o `feature_vector` final.

---

## 4. Interface de entrada

A testbench converte os bytes do PCAP para a interface do Packet Parser:

```text
TDATA[63:0]
TKEEP[7:0]
TVALID
TLAST
TUSER
timestamp_in[79:0]
```

Convenção utilizada:

```text
primeiro byte  → TDATA[7:0]
segundo byte   → TDATA[15:8]
...
oitavo byte    → TDATA[63:56]
```

Como o PCAP de referência utiliza Ethernet II:

```text
L3_OFFSET = 14
```

---

## 5. Reset

A integração utiliza reset:

```text
ativo em nível alto
síncrono
```

O mesmo sinal de reset é propagado para os módulos da cadeia integrada.

---

## 6. Timestamp

O timestamp segue o formato definido para a integração:

```text
timestamp[79:32] = segundos       (48 bits)
timestamp[31:0]  = nanossegundos (32 bits)
```

Como o PCAP utiliza segundos e microssegundos, a testbench converte:

```text
nanoseconds = microseconds × 1000
```

O Packet Parser apenas associa o timestamp ao pacote e o propaga para os módulos seguintes.

---

## 7. Configuração desta primeira campanha

Para isolar a validação funcional da questão de throughput, foi utilizado um intervalo deliberado entre os pacotes:

```text
80 clocks
```

Esse espaçamento foi adotado para permitir que FIU, Hash e Controller concluíssem o processamento antes da chegada do próximo pacote.

Portanto, esta campanha teve como objetivo:

```text
validar a integração funcional ponta a ponta
```

e não medir o throughput máximo da arquitetura.

---

## 8. Casos de teste

### Fluxo F1 — TCP

Pacotes:

```text
P01
P02
P03
```

Chave:

```text
src_ip   = 192.168.1.10
dst_ip   = 8.8.8.8
src_port = 52100
dst_port = 443
protocol = TCP (6)
```

Comprimentos IPv4:

```text
P01 = 40 bytes
P02 = 60 bytes
P03 = 52 bytes
```

Resultado esperado:

```text
packet_count = 3
byte_count   = 152
duration     = 500000 ns
```

---

### Fluxo F2 — UDP

Pacotes:

```text
P04
P05
```

Chave:

```text
src_ip   = 192.168.1.20
dst_ip   = 8.8.4.4
src_port = 40000
dst_port = 53
protocol = UDP (17)
```

Comprimentos:

```text
P04 = 28 bytes
P05 = 36 bytes
```

Resultado esperado:

```text
packet_count = 2
byte_count   = 64
duration     = 200000 ns
```

---

### Fluxo F3 — TCP

Pacotes:

```text
P06
P07
```

Chave:

```text
src_ip   = 10.0.0.1
dst_ip   = 10.0.0.2
src_port = 12345
dst_port = 80
protocol = TCP (6)
```

Comprimentos:

```text
P06 = 44 bytes
P07 = 80 bytes
```

Resultado esperado:

```text
packet_count = 2
byte_count   = 124
duration     = 900000 ns
```

---

### Fluxo F4 — UDP

Pacote:

```text
P08
```

Chave:

```text
src_ip   = 172.16.0.10
dst_ip   = 172.16.0.20
src_port = 5000
dst_port = 5001
protocol = UDP (17)
```

Resultado esperado:

```text
packet_count = 1
byte_count   = 28
duration     = 0
```

---

## 9. Resultado esperado da agregação

Os oito pacotes válidos devem resultar em quatro fluxos:

| Fluxo | Pacotes | packet_count | byte_count | duration |
|---|---|---:|---:|---:|
| F1 | P01, P02, P03 | 3 | 152 | 500000 ns |
| F2 | P04, P05 | 2 | 64 | 200000 ns |
| F3 | P06, P07 | 2 | 124 | 900000 ns |
| F4 | P08 | 1 | 28 | 0 ns |

Total:

```text
8 pacotes
4 fluxos
4 feature_vectors
```

---

## 10. Procedimento da testbench

A testbench realiza as seguintes etapas:

1. abre o arquivo `trafego_referencia_P01_P14.pcap`;
2. lê os oito primeiros registros;
3. converte os bytes para `TDATA`, `TKEEP`, `TVALID` e `TLAST`;
4. aplica `TUSER = 1` para os quadros válidos;
5. monta o timestamp no formato 48+32;
6. envia cada quadro ao Packet Parser;
7. aguarda 80 clocks entre os pacotes;
8. após P08, aguarda o processamento da última transferência;
9. gera um pulso de `pcap_done`;
10. o Controller inicia a varredura da Flow Table;
11. cada `fin_done` corresponde a um novo `feature_vector`;
12. a testbench compara automaticamente as features com os valores esperados para F1, F2, F3 e F4.

---

## 11. Critérios de PASS

Para a campanha ser considerada aprovada:

```text
P01 a P08 devem atravessar corretamente a cadeia;
```

e devem ser produzidas exatamente:

```text
4 features
```

correspondentes aos quatro fluxos esperados.

Cada feature deve possuir:

```text
flow_key correta
packet_count correto
byte_count correto
duration correta
```

Features duplicadas ou chaves desconhecidas são consideradas erro.

---

## 12. Resultado da campanha

A integração ponta a ponta foi executada com sucesso.

Resultado:

```text
8 pacotes de entrada
4 fluxos identificados
4 features corretas
```

A cadeia validada foi:

```text
PCAP
→ Packet Parser
→ FIU
→ Hash
→ Controller
→ Flow Table
→ Flow Finalizer
→ feature_vector
```

Os pacotes pertencentes à mesma uniflow foram corretamente agregados na mesma entrada da Flow Table.

Isso permitiu validar não apenas a passagem dos metadados entre os módulos, mas também:

```text
MISS
HIT
atualização de packet_count
atualização de byte_count
atualização do último timestamp
cálculo de duration
geração do feature_vector
```

---

## 13. Importância do teste

Antes desta campanha, a frente de Features já havia sido validada utilizando vetores de metadados aplicados diretamente na entrada da FIU/Hash.

Este teste acrescentou o Packet Parser à frente da cadeia.

Assim, a entrada passou a ser um pacote real proveniente do PCAP:

```text
bytes Ethernet/IPv4/TCP/UDP
```

e a saída passou a ser o vetor final de features.

Isso caracteriza a primeira validação funcional ponta a ponta do sistema com o Packet Parser integrado.

---

## 14. Limitação desta campanha

A campanha utilizou:

```text
80 clocks de intervalo entre os pacotes
```

Portanto, o resultado demonstra:

```text
correção funcional da integração: VALIDADA
```

mas não demonstra:

```text
throughput máximo da arquitetura: NÃO VALIDADO NESTA CAMPANHA
```

Posteriormente, testes sem folga entre pacotes mostraram que a Hash Unit pode ainda estar ocupada quando uma nova transferência chega.

Esse comportamento deve ser tratado separadamente da validação funcional realizada aqui.

---

## 15. Conclusão

A primeira campanha ponta a ponta com os módulos da frente de Features foi concluída com sucesso utilizando os pacotes P01 a P08.

Os oito pacotes válidos foram processados desde a interface de entrada do Packet Parser até a geração dos vetores finais pelo Flow Finalizer.

Foram corretamente produzidos quatro fluxos:

```text
F1 → 3 pacotes, 152 bytes, 500000 ns
F2 → 2 pacotes,  64 bytes, 200000 ns
F3 → 2 pacotes, 124 bytes, 900000 ns
F4 → 1 pacote,   28 bytes, 0 ns
```

Resultado final:

```text
8 pacotes processados
4 fluxos agregados
4 feature_vectors corretos
```

Dessa forma, considera-se validada a integração funcional:

```text
Packet Parser
→ FIU
→ Hash
→ Controller
→ Flow Table
→ Flow Finalizer
```

nas condições desta campanha.
