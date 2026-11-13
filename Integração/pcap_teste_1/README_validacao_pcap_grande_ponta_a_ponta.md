# Validação Ponta a Ponta com PCAP Grande

## 1. Objetivo

Validar a cadeia completa de extração de features utilizando um PCAP de maior volume, exercitando de forma integrada:

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

O objetivo desta campanha foi verificar a estabilidade funcional da integração em volume, preservando o espaçamento de 80 ciclos de clock entre quadros utilizado na validação anterior da frente de Features.

Este teste não tem como objetivo determinar ainda o throughput máximo da arquitetura. A análise de pacotes consecutivos e redução progressiva do intervalo entre transferências deve ser realizada em campanha separada.

---

## 2. Arquivo de entrada

Foi utilizado o PCAP grande já empregado anteriormente na validação do Packet Parser:

```text
teste.pcap
```

Características relevantes:

- formato PCAP clássico;
- enlace DLT_NULL / loopback;
- `L3_OFFSET = 4`;
- foram processados os primeiros **10.000 registros**;
- os quadros foram convertidos pela testbench para a interface de entrada do Packet Parser.

A escolha dos primeiros 10.000 registros permite comparação direta com a campanha anterior do Parser, na qual haviam sido observados **7.418 pacotes válidos**.

---

## 3. Configuração da simulação

Configuração principal:

```text
Registros processados : 10.000
L3_OFFSET             : 4
Gap entre quadros     : 80 clocks
TUSER                 : 1 para os quadros enviados
Flow Table            : 65.536 entradas
```

O timestamp utilizado segue o contrato definido para a integração:

```text
timestamp[79:32] = segundos (48 bits)
timestamp[31:0]  = nanossegundos (32 bits)
```

Os timestamps do PCAP, originalmente em segundos e microssegundos, são convertidos pela testbench:

```text
nanoseconds = microseconds × 1000
```

---

## 4. Arquitetura testada

A campanha utilizou o seguinte caminho completo:

```text
teste.pcap
    ↓
AXI Stream
TDATA / TKEEP / TVALID / TLAST / TUSER / timestamp
    ↓
Packet Parser
    ↓
src_ip
dst_ip
src_port
dst_port
protocol
packet_length
timestamp
valid
    ↓
Flow Identification Unit
    ↓
flow_key
packet_length
timestamp
valid
    ↓
Hash Unit
    ↓
hash_index
flow_key
packet_length
timestamp
hash_valid
    ↓
Controller
    ↓
Flow Table
    ↓
Flow Finalizer
    ↓
feature_vector
```

Ao final da entrada dos pacotes, a testbench ativa `pcap_done`, iniciando a varredura da Flow Table e a geração dos vetores finais de features.

---

## 5. Critérios de validação

Durante a entrada dos 10.000 registros foram monitorados:

- quantidade de registros enviados;
- quantidade de pulsos `valid` gerados pelo Packet Parser;
- quantidade de lookups concluídos pelo Controller;
- quantidade de ocorrências de MISS;
- quantidade de ocorrências de HIT;
- quantidade de COLLISION.

Após `pcap_done`, foram monitorados:

- conclusão da varredura da Flow Table;
- quantidade de `feature_vector` produzidos;
- conteúdo das features gravado em CSV.

Foi utilizado como critério principal de ausência de perda entre o Parser e o Controller:

```text
lookup_count == parser_valid_count
```

---

## 6. Resultados observados

A evolução da campanha confirmou que todos os pacotes liberados pelo Parser chegaram ao Controller.

Resultado final:

| Métrica | Resultado |
|---|---:|
| Registros PCAP enviados | 10.000 |
| Pacotes válidos liberados pelo Parser | 7.418 |
| Lookups concluídos | 7.418 |
| MISS | 1.048 |
| HIT | 6.348 |
| COLLISION | 22 |
| Features geradas | 1.048 |

O resultado do Parser reproduziu exatamente a campanha anterior:

```text
Parser valid = 7.418
```

Não foi observada perda entre o Packet Parser e o Controller:

```text
Parser valid = 7.418
Lookups      = 7.418
```

---

## 7. Consistência dos resultados

A soma das classificações realizadas pelo Controller fecha exatamente com a quantidade de pacotes válidos:

```text
MISS + HIT + COLLISION
1048 + 6348 + 22
= 7418
```

Os pacotes classificados como MISS criam novos fluxos.

Os pacotes classificados como HIT atualizam fluxos já existentes.

Os pacotes classificados como COLLISION não são incorporados às entradas existentes segundo a política atual.

Assim, a quantidade de pacotes efetivamente agregados nos fluxos armazenados é:

```text
MISS + HIT
1048 + 6348
= 7396 pacotes
```

A análise do arquivo `features_pcap_grande.csv` confirma que a soma dos campos `packet_count` das 1.048 features também é:

```text
7396
```

Portanto:

```text
7396 pacotes agregados aos fluxos
+ 22 colisões
= 7418 pacotes válidos
```

Esse fechamento confirma a consistência entre Parser, FIU, Hash, Controller, Flow Table e Finalizer.

---

## 8. Características dos fluxos produzidos

O arquivo CSV final contém:

```text
1.048 features
1.048 feature_id distintos
1.048 flow_key distintas
```

Distribuição observada:

| Característica | Resultado |
|---|---:|
| Fluxos com apenas 1 pacote | 52 |
| Fluxos com mais de 1 pacote | 996 |
| Maior `packet_count` observado | 192 |
| Soma de todos os `packet_count` | 7.396 |

Isso demonstra que a campanha não validou apenas a criação de fluxos, mas também exercitou extensivamente o caminho de HIT e a atualização dos estados armazenados na Flow Table.

---

## 9. Varredura e geração das features

Após o processamento dos 10.000 registros, a testbench gerou um pulso de:

```text
pcap_done
```

O Controller iniciou a varredura da Flow Table e o Finalizer produziu os vetores finais.

O sinal `scan_done` foi observado após:

```text
227.002 clocks
```

Foram geradas:

```text
1.048 features
```

O resultado foi salvo no arquivo:

```text
features_pcap_grande.csv
```

Formato:

```text
feature_id,
flow_key_hex,
packet_count,
byte_count,
duration_hex
```

---

## 10. Resultado da campanha

O Transcript apresentou:

```text
PASS: cadeia ponta a ponta processou a campanha sem perda entre Parser e Controller.
```

A campanha demonstrou com sucesso o funcionamento integrado de:

```text
Packet Parser
+
FIU
+
Hash Unit
+
Controller
+
Flow Table
+
Flow Finalizer
```

para um conjunto de **10.000 registros de PCAP**, dos quais **7.418 foram aceitos pelo Parser**.

Todos os 7.418 pacotes válidos foram processados pelo Controller.

A classificação final foi:

```text
MISS      = 1.048
HIT       = 6.348
COLLISION = 22
```

e foram produzidas:

```text
1.048 features
```

sem perda observada entre o Parser e o Controller nas condições desta campanha.

---

## 11. Limitação desta validação

O resultado demonstra a correção funcional da cadeia completa **com intervalo de 80 clocks entre os quadros**.

Portanto, esta campanha não demonstra ainda que a arquitetura suporte tráfego contínuo ou pacotes consecutivos sem espaçamento.

O teste anterior Parser + FIU + Hash sem folga já demonstrou que a Hash Unit pode receber uma nova transferência enquanto ainda está ocupada, produzindo:

```text
PROTOCOL_VIOLATION
```

Assim, o resultado deste README deve ser interpretado como:

```text
Integração ponta a ponta funcional com espaçamento controlado: VALIDADA.
Throughput máximo da arquitetura: AINDA NÃO VALIDADO.
```

---

## 12. Próximos testes

A próxima campanha deverá utilizar o mesmo PCAP e a mesma arquitetura, reduzindo progressivamente o intervalo entre quadros:

```text
80 → 40 → 20 → 16 → 15 → 10 → 0 clocks
```

Para cada configuração deverão ser registrados:

- pacotes válidos liberados pelo Parser;
- lookups concluídos;
- MISS;
- HIT;
- COLLISION;
- ocorrência de `PROTOCOL_VIOLATION`;
- features geradas;
- eventual perda de pacotes.

Esse procedimento permitirá determinar experimentalmente o intervalo mínimo suportado pela arquitetura atual e avaliar objetivamente a necessidade de FIFO, handshake ou aumento do throughput dos módulos.

---

## 13. Conclusão

A campanha com o PCAP grande validou com sucesso a integração completa do sistema nas condições funcionais adotadas.

Foram processados **10.000 registros**, com **7.418 pacotes válidos**, sem perda entre o Packet Parser e o Controller. A classificação dos pacotes fechou exatamente com os valores de MISS, HIT e COLLISION, e a análise das **1.048 features** confirmou a consistência dos contadores de pacotes armazenados.

Dessa forma, considera-se **validada a integração ponta a ponta em volume com intervalo de 80 clocks entre quadros**.

A etapa seguinte é a caracterização do throughput, reduzindo o espaçamento entre pacotes até identificar o limite da arquitetura.
