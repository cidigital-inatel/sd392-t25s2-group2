# Resultados da Semana 6 na integração FIU e Hash

Projeto CI Digital Inatel, T25S2, Grupo 2. Responsáveis acadêmicos: Bruno e Samuel. Referência principal: `Semana_6.docx`, seção 2.3 e regras da seção 3. Execução: 22/10/2026 às 21:32:25, UTC-03:00.

Os dois módulos e o top integrado foram compilados e simulados com sucesso. Os testes cobrem recepção, montagem da chave, envio FIU para Hash, geração do CRC, associação dos metadados e publicação da saída. Cada execução conferiu os 181 vetores originais e cinco operações adicionais entregues.

1. **Ambiente e versão efetivamente verificados.**

| Item | Configuração |
|---|---|
| Referência da atividade | Semana 6, de 19 a 25 de outubro de 2026 |
| Protocolo | Uma captura por período alto de validade; rearme após baixo amostrado; `start` interno |
| Clock e reset | Clock comum, período de teste de 10 ns; reset síncrono ativo baixo |
| Dados FIU para Hash | Chave 104, comprimento 16 e timestamp 80 bits |
| Saída Hash | Índice 16 e os 200 bits de dados associados |
| CRC | CCITT-FALSE; `poly=1021`, `init=FFFF`, sem reflexão, `xorout=0000` |
| Simulador | Verilator 5.49, conforme o relatório de execução |
| Identificação | `rev vUNKNOWN-built20260516-4e853d8` |
| Distribuição instalada | Pacote Python `verilator` 5.48.0 |
| Modelo de referência | Python 3.12.14, biblioteca padrão `binascii.crc_hqx` |

O lint do top e dos dois módulos passou com `--lint-only -Wall`. As três compilações nominais usaram `--binary --timing --trace --assert -Wall -Wno-BLKSEQ`, com retorno zero e sem avisos do Verilator. `BLKSEQ` permite as atribuições bloqueantes da testbench. A supressão não é aplicada ao lint dos RTLs.

2. **Contagens observadas em cada teste.**

| Indicador | FIU isolada | Hash isolado | Integração |
|---|---|---|---|
| Entradas capturadas | 189 | 189 | 190 |
| Entregas conferidas | 186 | 186 | 186 |
| Cancelados por reset | 3 | 3 | 4 |
| Pendentes ao final | 0 | 0 | 0 |
| Máximo de registros em andamento | 1 | 1 | 2 |
| Transferências da FIU | 186 | 0 | 188 |
| Capturas do Hash | 0 | 189 | 188 |
| Ciclos altos adicionais ignorados | 51 | 51 | 51 |
| Ciclos verificando start | 719 | 3202 | 3216 |
| Intervalos mínimos exercitados | 155 | 156 | 157 |

Na FIU isolada, cada entrega compara chave, comprimento e timestamp, totalizando 200 bits. No Hash isolado e na integração, também se compara o índice, totalizando 216 bits. As 558 entregas somam 186 em cada execução; 372 dessas comparações incluem CRC.

Na integração, `190 = 186 + 4 + 0`: entradas capturadas, entregas, cancelamentos por reset e pendências. As 188 transferências FIU para Hash correspondem a 188 capturas efetivamente verificadas nos registradores do Hash. Duas dessas operações são canceladas após chegar ao Hash; duas entradas adicionais são canceladas ainda na FIU.

A execução integrada chegou a dois registros em andamento, um em cada unidade. Esse cenário foi exercitado com intervalo de 16 clocks entre entradas, sem FIFO de hardware. A estrutura de valores esperados pertence exclusivamente à testbench.

3. **Valores conhecidos da integração.**

Os valores obtidos foram extraídos de `validation/integracao_obtidos.csv`, fase `colecao`. Os demais 168 vetores também passaram.

| ID | Caso | Esperado | Obtido | Estado |
|---|---|---|---|---|
| 0 | tcp_exemplo_FI | `B511` | `B511` | PASS |
| 1 | mesma_chave_outros_metadados | `B511` | `B511` | PASS |
| 2 | fluxo_reverso | `EB45` | `EB45` | PASS |
| 3 | udp_dns | `890D` | `890D` | PASS |
| 4 | pesquisa_dst_32 | `83A4` | `83A4` | PASS |
| 5 | pesquisa_dst_33 | `C604` | `C604` | PASS |
| 6 | pesquisa_dst_34 | `08E4` | `08E4` | PASS |
| 7 | pesquisa_dst_35 | `4D44` | `4D44` | PASS |
| 8 | parser_pesquisa | `A018` | `A018` | PASS |
| 9 | fronteira_zero | `280C` | `280C` | PASS |
| 10 | fronteira_um | `FED3` | `FED3` | PASS |
| 11 | ascii_13_bytes | `36CC` | `36CC` | PASS |
| 12 | colisao_indice_chave_distinta | `B511` | `B511` | PASS |

O caso 0 usa TCP de `192.168.1.10:50000` para `192.168.1.20:443`, chave `C0A8010AC0A80114C35001BB06` e índice `B511`. O caso 1 repete a chave com outros metadados. O caso 12 usa outra chave com o mesmo índice. Chaves e metadados próprios foram preservados em todas as entregas.

A referência e os arquivos de vetores são idênticos aos do ZIP anexo, byte a byte. O padrão de nove bytes `123456789` com resultado `29B1` é uma conferência do modelo Python; o RTL recebe 13 bytes. O caso ASCII de 13 bytes é o ID 11, com resultado `36CC`.

O CSV `validation/casos_integracao.csv` organiza os 181 casos com IPs, portas, protocolo, comprimento, timestamp, chave e CRC esperado/obtido. Os CSVs brutos conservam também as operações extras de latência e validade prolongada.

4. **Temporização e regra de validade confirmadas.**

| Medida | FIU | Hash | Caminho integrado |
|---|---|---|---|
| Captura até disponibilidade | 1 clock | 14 clocks | 16 clocks |
| Captura até leitura na saída | 2 clocks | 15 clocks | 17 clocks |
| Intervalo mínimo de entradas com pulso de um ciclo | 3 clocks | 16 clocks | 16 clocks |

O primeiro registro integrado foi capturado no ciclo 5 e lido no ciclo 22: 17 clocks. Os tempos foram 45 ns e 215 ns. A FIU publicou após 55 ns; o Hash capturou a 65 ns; o resultado ficou disponível após 205 ns. A figura do guia foi extraída do VCD real da execução.

Cada unidade passou com validade alta por dois, cinco e 24 clocks, capturando uma vez por período alto. Os 51 ciclos altos adicionais são `23 + 1 + 4 + 23`, correspondentes às quatro operações prolongadas de 24, dois, cinco e 24 clocks. A validade voltou a baixo antes de cada nova operação.

O caso de 24 clocks mantém o sinal alto depois do término do processamento. A ausência de repetição confirma que ficar livre novamente não rearma a leitura: é necessário observar validade baixa. O produtor deve respeitar tanto o intervalo de capacidade quanto esse rearme.

5. **Resets, testes negativos e reprodução das correções.**

Os resets dos testes unitários cancelaram três operações por unidade. Na integração, o reset final foi aplicado com dois registros em andamento, totalizando quatro cancelamentos ao longo do teste. Nenhum registro cancelado reapareceu depois do reset.

| Verificação adicional | Resultado |
|---|---|
| Nova entrada com FIU ocupada | `PROTOCOL_VIOLATION` detectada |
| Nova entrada com Hash ocupado | `PROTOCOL_VIOLATION` detectada |
| FIU envia em intervalo de três clocks para o Hash | Violação detectada no Hash |
| Hash anterior recebe validade prolongada | Incompatibilidade antiga reproduzida |
| FIU anterior recebe validade prolongada | Repetição antiga reproduzida |
| Mesmo estímulo nos dois RTLs da Semana 6 | Uma entrega por período alto; PASS |

Os testes negativos de capacidade devem terminar com erro específico, e o executor exige esse diagnóstico. Os logs de baseline registram as incompatibilidades anteriores. Eles têm interpretação diferente dos logs nominais, que devem terminar em PASS. O documento de falhas detalha cada caso.

Trecho integral das confirmações da simulação integrada:

```text
PASS: kind=2 captura, start e latencia de 17 clocks.
PASS: resets cancelam registros em captura, processamento e publicacao.
PASS: valid alto por 2, 5 e 24 clocks gera uma captura; baixo rearma.
PASS: 181 vetores, todos os dados, ordem e pulsos conferidos.
SUMMARY accepted=190 delivered=186 reset_cancelled=4 pending=0
SUMMARY fiu_transfers=188 hash_captures=188 max_pending=2
SUMMARY repeated_high_cycles=51 start_checks=3216 minimum_gap_checks=157 availability_checks=187
PASS: Semana 6 kind=2 concluida sem divergencias.
```

6. **Reprodução, identidade e alcance da evidência.**

Comandos a partir da raiz do pacote, com Verilator e seus pré-requisitos disponíveis:

```bash
python3 python/run_tests.py
python3 python/run_regressions.py
python3 python/report_results.py
```

O ModelSim ou Questa pode executar o teste nominal com `do run_modelsim.do`. O script prepara também a seleção dos testes unitários e mantém seus arquivos em `validation/modelsim/`. Essa ferramenta não foi executada neste ambiente; a evidência registrada pertence ao Verilator.

Os hashes abaixo identificam os RTLs usados nas três simulações:

```text
rtl/flow_identification_unit.sv
3f9ae10837bd954211f3f9643b29bd86acc35ee395a21dd9e779c5ae6ba5bc8c

rtl/hash_unit.sv
30b79cbef9b3ba8b8de5fd10806bf6fa77c927751e5a3a17f151ce2bda051ee1

rtl/fiu_hash_top.sv
d6f412178c05d0adb0770f401f7ad73374208756e552380f6cd28152d0e0c220
```

`validation/summary.json` identifica também os arquivos de teste, o modelo e os vetores. `validation/regressions/summary.json` identifica os baselines e as versões corrigidas usadas nos testes antes/depois. O manifesto do pacote cobre os demais arquivos.

O alcance comprovado é funcional e isolado do restante do sistema: origem dos metadados e consumidor final são representados pela testbench. Não foram medidas área, frequência máxima ou temporização da FPGA física. As figuras derivam dos VCDs; os resultados obtidos dos CSVs foram registrados pelas saídas reais dos módulos simulados.
