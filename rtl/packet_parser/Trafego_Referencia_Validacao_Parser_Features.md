# Especificação do Tráfego de Referência para Validação do Parser e da Extração de Features

## 1. Objetivo

Definir um conjunto ordenado e reproduzível de pacotes e fluxos para validar:

- a extração dos metadados pelo **Packet Parser**;
- a identificação de pacotes pertencentes ao mesmo fluxo ou a fluxos distintos;
- o comportamento da etapa de extração de features diante de diferentes quantidades de pacotes, tamanhos e durações;
- o processamento de quadros com diferentes comprimentos;
- o tratamento de pacotes fora do escopo e quadros inválidos.

O conjunto de tráfego foi organizado de forma que os mesmos pacotes possam ser reutilizados nos testes unitários do Parser e, posteriormente, nos testes de integração com o **Flow Identification Unit**, **Hash Unit** e o sistema de extração de features.

---

## 2. Premissas utilizadas

A interface de saída do Packet Parser considerada nesta especificação é:

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

O sinal anteriormente denominado `metadata_valid` foi padronizado como:

```text
valid
```

Para esta primeira versão:

- são aceitos quadros Ethernet II contendo IPv4;
- são aceitos protocolos TCP e UDP;
- pacotes IPv4 fragmentados são descartados;
- quadros inválidos indicados por `TUSER = 0` são descartados;
- protocolos fora de TCP/UDP não geram metadados válidos;
- `packet_length` corresponde ao campo **IPv4 Total Length**;
- o timestamp é representado com 80 bits em nanossegundos;
- os fluxos são considerados unidirecionais;
- a chave de fluxo é formada por:

```text
src_ip + dst_ip + src_port + dst_port + protocol
```

Para os cálculos de features deste documento:

```text
packet_count = número de pacotes válidos pertencentes ao fluxo

byte_count = soma dos valores de packet_length dos pacotes válidos do fluxo

duration = timestamp do último pacote - timestamp do primeiro pacote
```

---

# 3. Fluxos de referência

## F1 — Fluxo TCP com três pacotes

```text
src_ip   = 192.168.1.10
dst_ip   = 8.8.8.8
src_port = 52100
dst_port = 443
protocol = 6 (TCP)
```

Pacotes:

```text
P01
P02
P03
```

Objetivos principais:

- validar múltiplos pacotes pertencentes ao mesmo fluxo;
- validar diferentes tamanhos de pacotes;
- validar atualização de `packet_count`;
- validar atualização de `byte_count`;
- validar cálculo de duração.

---

## F2 — Fluxo UDP com dois pacotes

```text
src_ip   = 192.168.1.20
dst_ip   = 8.8.4.4
src_port = 40000
dst_port = 53
protocol = 17 (UDP)
```

Pacotes:

```text
P04
P05
```

Objetivos principais:

- validar UDP;
- validar um segundo fluxo distinto;
- validar dois pacotes pertencentes ao mesmo fluxo UDP;
- validar pacote cujo tamanho total do quadro não é múltiplo de 8 bytes.

---

## F3 — Fluxo TCP com IHL variável

```text
src_ip   = 10.0.0.1
dst_ip   = 10.0.0.2
src_port = 12345
dst_port = 80
protocol = 6 (TCP)
```

Pacotes:

```text
P06
P07
```

Objetivos principais:

- validar `IHL > 5`;
- validar cálculo dinâmico de `transport_offset`;
- validar que dois pacotes com a mesma 5-tupla pertencem ao mesmo fluxo mesmo com tamanhos de cabeçalho IPv4 diferentes.

---

## F4 — Fluxo UDP de pacote único

```text
src_ip   = 172.16.0.10
dst_ip   = 172.16.0.20
src_port = 5000
dst_port = 5001
protocol = 17 (UDP)
```

Pacote:

```text
P08
```

Objetivos principais:

- validar fluxo contendo apenas um pacote;
- validar `duration = 0`;
- fornecer contraste com fluxos de múltiplos pacotes.

---

# 4. Pacotes fora do escopo e quadros inválidos

Os pacotes abaixo não devem gerar uma entrada válida para a etapa seguinte.

```text
P09  — IPv4 com protocolo não suportado
P10  — EtherType diferente de IPv4
P11  — IPv4 fragmentado
P12  — quadro com TUSER = 0
P13  — IPv4 com IHL < 5
P14  — quadro truncado com TLAST antecipado
```

Esses pacotes não pertencem aos fluxos válidos F1–F4.

---

# 5. Lista ordenada dos pacotes

| Pacote | Fluxo | Tipo | IPv4 Total Length | Ethernet bytes | Timestamp (ns) | Cenário principal |
|---|---|---|---:|---:|---:|---|
| **P01** | F1 | TCP | 40 | 54 | 1_000_000_000 | TCP válido; início de fluxo |
| **P02** | F1 | TCP | 60 | 74 | 1_000_100_000 | Mesmo fluxo; tamanho diferente |
| **P03** | F1 | TCP | 52 | 66 | 1_000_500_000 | Mesmo fluxo; duração e byte_count |
| **P04** | F2 | UDP | 28 | 42 | 2_000_000_000 | UDP válido; novo fluxo |
| **P05** | F2 | UDP | 36 | 50 | 2_000_200_000 | Mesmo fluxo UDP; tamanho diferente |
| **P06** | F3 | TCP, IHL=6 | 44 | 58 | 3_000_000_000 | IHL > 5; transport_offset=38 |
| **P07** | F3 | TCP, IHL=15 | 80 | 94 | 3_000_900_000 | IHL máximo; transport_offset=74 |
| **P08** | F4 | UDP | 28 | 42 | 4_000_000_000 | Fluxo de pacote único |
| **P09** | — | IPv4 / protocolo não suportado | 28 | 42 | 5_000_000_000 | Protocolo fora de TCP/UDP |
| **P10** | — | Não IPv4 | — | definido pelo quadro | 5_100_000_000 | EtherType fora do escopo |
| **P11** | — | IPv4 fragmentado | 40 | 54 | 5_200_000_000 | MF=1 ou Fragment Offset != 0 |
| **P12** | — | TCP com quadro inválido | 40 | 54 | 5_300_000_000 | TUSER=0 |
| **P13** | — | IPv4 malformado | definido no teste | definido no teste | 5_400_000_000 | IHL < 5 |
| **P14** | — | Quadro truncado | incompleto | incompleto | 5_500_000_000 | TLAST antecipado |

> `Ethernet bytes = 14 + IPv4 Total Length` para os quadros Ethernet II/IPv4 sem VLAN.

---

# 6. Valores esperados dos metadados

## 6.1 Pacotes válidos

| Pacote | src_ip | dst_ip | src_port | dst_port | protocol | packet_length | timestamp (ns) | valid |
|---|---|---|---:|---:|---:|---:|---:|---:|
| **P01** | 192.168.1.10 | 8.8.8.8 | 52100 | 443 | 6 | 40 | 1_000_000_000 | 1 |
| **P02** | 192.168.1.10 | 8.8.8.8 | 52100 | 443 | 6 | 60 | 1_000_100_000 | 1 |
| **P03** | 192.168.1.10 | 8.8.8.8 | 52100 | 443 | 6 | 52 | 1_000_500_000 | 1 |
| **P04** | 192.168.1.20 | 8.8.4.4 | 40000 | 53 | 17 | 28 | 2_000_000_000 | 1 |
| **P05** | 192.168.1.20 | 8.8.4.4 | 40000 | 53 | 17 | 36 | 2_000_200_000 | 1 |
| **P06** | 10.0.0.1 | 10.0.0.2 | 12345 | 80 | 6 | 44 | 3_000_000_000 | 1 |
| **P07** | 10.0.0.1 | 10.0.0.2 | 12345 | 80 | 6 | 80 | 3_000_900_000 | 1 |
| **P08** | 172.16.0.10 | 172.16.0.20 | 5000 | 5001 | 17 | 28 | 4_000_000_000 | 1 |

## 6.2 Pacotes descartados ou inválidos

| Pacote | Condição | Resultado esperado |
|---|---|---|
| **P09** | IPv4 com protocolo diferente de TCP/UDP | `valid = 0` |
| **P10** | EtherType diferente de `0x0800` | `valid = 0` |
| **P11** | IPv4 fragmentado | `drop_packet = 1`, `valid = 0` |
| **P12** | `TUSER = 0` no final do quadro | `valid = 0` |
| **P13** | `IHL < 5` | `valid = 0` |
| **P14** | `TLAST` antes da extração dos campos necessários | `valid = 0` |

Os valores das demais saídas após um pacote descartado não devem ser interpretados como novos metadados, pois a indicação de validade permanece desativada.

---

# 7. Features esperadas por fluxo

| Fluxo | Pacotes | packet_count | byte_count | Primeiro timestamp | Último timestamp | duration |
|---|---|---:|---:|---:|---:|---:|
| **F1** | P01, P02, P03 | 3 | 152 bytes | 1_000_000_000 ns | 1_000_500_000 ns | 500_000 ns |
| **F2** | P04, P05 | 2 | 64 bytes | 2_000_000_000 ns | 2_000_200_000 ns | 200_000 ns |
| **F3** | P06, P07 | 2 | 124 bytes | 3_000_000_000 ns | 3_000_900_000 ns | 900_000 ns |
| **F4** | P08 | 1 | 28 bytes | 4_000_000_000 ns | 4_000_000_000 ns | 0 ns |

Cálculos:

```text
F1:
packet_count = 3
byte_count   = 40 + 60 + 52 = 152 bytes
duration     = 1_000_500_000 - 1_000_000_000
             = 500_000 ns
```

```text
F2:
packet_count = 2
byte_count   = 28 + 36 = 64 bytes
duration     = 2_000_200_000 - 2_000_000_000
             = 200_000 ns
```

```text
F3:
packet_count = 2
byte_count   = 44 + 80 = 124 bytes
duration     = 3_000_900_000 - 3_000_000_000
             = 900_000 ns
```

```text
F4:
packet_count = 1
byte_count   = 28 bytes
duration     = 0 ns
```

---

# 8. Cenários cobertos por pacote

| Cenário | Pacotes |
|---|---|
| IPv4 + TCP válido | P01, P02, P03, P06, P07 |
| IPv4 + UDP válido | P04, P05, P08 |
| Pacotes do mesmo fluxo | P01–P03; P04–P05; P06–P07 |
| Fluxos distintos | F1, F2, F3 e F4 |
| Fluxo com 1 pacote | P08 / F4 |
| Fluxo com 2 pacotes | P04–P05 / F2; P06–P07 / F3 |
| Fluxo com 3 pacotes | P01–P03 / F1 |
| Diferentes `packet_length` | P01–P08 |
| Diferentes durações | F1, F2, F3 e F4 |
| Quadro com múltiplas transferências de 64 bits | P01–P08 |
| Comprimento do quadro não múltiplo de 8 bytes | P01–P08 em diferentes resíduos |
| `IHL > 5` | P06 |
| `IHL = 15` | P07 |
| Protocolo fora do escopo | P09 |
| EtherType fora do escopo | P10 |
| IPv4 fragmentado | P11 |
| Quadro inválido por TUSER | P12 |
| IHL inválido | P13 |
| Quadro truncado | P14 |

---

# 9. Relação com os testes unitários do Packet Parser

O conjunto de tráfego acima complementa a tabela de testes unitários já definida.

A tabela de testes unitários descreve **o comportamento que deve ser verificado**.

Esta especificação define **quais pacotes e fluxos concretos serão utilizados para realizar essas verificações**.

Exemplo:

```text
UT-01 — IPv4 + TCP válido
        ↓
P01

UT-02 — IPv4 + UDP válido
        ↓
P04

UT-03 — IPv4 com IHL > 5
        ↓
P06

UT-13 — IPv4 com IHL = 15
        ↓
P07
```

Alguns testes, como reset durante um quadro, pacotes consecutivos sem ciclo ocioso e TKEEP em posições específicas, são condições de aplicação dos estímulos e não exigem necessariamente um novo conteúdo de pacote.

---

# 10. Sequência sugerida para a primeira campanha de testes

Uma sequência inicial pode utilizar:

```text
P01
P02
P03
P04
P05
P06
P07
P08
P09
P10
P11
P12
P13
P14
```

Essa ordem permite começar pelos fluxos válidos e, posteriormente, aplicar os casos de descarte.

Para testes específicos de operação contínua, a mesma lista pode ser reorganizada. Por exemplo:

```text
P01 → P04 → P02 → P05 → P03
```

permitindo verificar a alternância entre fluxos distintos enquanto seus estados permanecem ativos no sistema de extração de features.

---

# 11. Entregáveis atendidos

Com esta especificação ficam definidos:

- [x] **Lista ordenada dos pacotes e fluxos selecionados**;
- [x] **Identificação dos cenários cobertos por cada pacote**;
- [x] **Valores esperados dos metadados para os casos de teste definidos**;
- [x] **Valores esperados das features dos fluxos válidos**.

O próximo passo é transformar essa especificação em tráfego sintético reproduzível e executar os casos no ambiente de simulação.
