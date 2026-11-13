# Semana 8 - Validação da integração FIU/Hash, Controller, Flow Table e Finalizer

**Projeto:** Extração de Features de Fluxos TCP/IP para IDS baseados em ML  
**Ferramenta:** ModelSim Intel FPGA Starter Edition 2020.1  
**Data da execução:** 11/11/2026  
**Responsáveis pela FIU e pelo Hash:** Bruno e Samuel

## 1. Escopo

Este registro documenta a reprodução, no ModelSim de Bruno, do teste integrado da FIU/Hash com Controller, Flow Table e Flow Finalizer. Os estímulos vêm do arquivo `hash_vectors.mem` e são aplicados pelo testbench `tb_top_extracao_features_com_entrada.sv`. **O Packet Parser não está incluído nesta simulação**; portanto, o resultado não constitui validação ponta a ponta desde a interface AXI Stream do Parser.

## 2. Arquivos e preparação

A pasta de fontes contém `rtl/controller_base.sv`, `rtl/fiu_hash_top.sv`, `rtl/flow_finalizer.sv`, `rtl/flow_identification_unit.sv`, `rtl/flow_table.sv`, `rtl/hash_unit.sv` e `rtl/top_extracao_features_entrada.sv`. Em `tb` estão `tb_fiu_hash_semana8.sv` e `tb_top_extracao_features_com_entrada.sv`. Para o teste descrito aqui, o módulo simulado é `tb_top_extracao_features_com_entrada`.

| Arquivo | Função | Participação |
|---|---|---|
| `rtl/flow_identification_unit.sv` | Forma a chave de fluxo a partir dos metadados | RTL FIU |
| `rtl/hash_unit.sv` | Calcula o índice de hash/CRC16 | RTL Hash |
| `rtl/fiu_hash_top.sv` | Integra FIU e Hash | RTL integração |
| `rtl/controller_base.sv` | Controla lookup, atualização e varredura | RTL Controller |
| `rtl/flow_table.sv` | Armazena as entradas dos fluxos | RTL Flow Table |
| `rtl/flow_finalizer.sv` | Gera o vetor de features | RTL Finalizer |
| `rtl/top_extracao_features_entrada.sv` | Interliga FIU/Hash, Controller, Flow Table e Finalizer | RTL top |
| `tb/tb_top_extracao_features_com_entrada.sv` | Aplica 181 vetores e confere os resultados | Testbench executado |
| `tb/tb_fiu_hash_semana8.sv` | Teste isolado anterior de FIU/Hash | Presente no projeto; não executado neste teste |
| `hash_vectors.mem` | Dados dos 181 pacotes e hash esperado | Arquivo lido pelo testbench |

O testbench contém `$readmemh("hash_vectors.mem", vectors);`. Como `pwd` no Transcript indicou `C:/semana8_integracao_fiu_hash_controller_finalizer_projeto`, uma cópia de `hash_vectors.mem` foi colocada na raiz dessa pasta de projeto. O arquivo de vetores não é um módulo compilável.

Na primeira tentativa de `Compile All`, `top_extracao_features_entrada.sv` apresentou 11 erros `vlog-2892` relativos às entradas com `` `default_nettype none``. As declarações das portas de entrada foram ajustadas para `input wire logic`, mantendo nomes e larguras. Na segunda tentativa: **9 compilações, 0 falhas, 0 erros**. A linha de erro antiga permanece no histórico do Transcript, mas não integra o resultado final.

## 3. Execução

```tcl
pwd
vsim -onfinish stop work.tb_top_extracao_features_com_entrada
run -all
```

Para observar a Wave, foram adicionados `dut/clk`, `dut/rst`, `dut/fin_valid`, `dut/fin_done` e `dut/feature_vector`; a simulação foi reiniciada e executada novamente para registrar o histórico. A Wave ampliada mostra ciclos de clock, atividade de `fin_valid` e `fin_done` e um valor definido de `feature_vector` em hexadecimal. A inspeção visual é evidência complementar aos checks automáticos do testbench.

## 4. Resultados

| Indicador | Esperado | Observado |
|---|---:|---:|
| Pacotes enviados | 181 | 181 |
| MISS | 179 | 179 |
| HIT | 1 | 1 |
| COLLISION | 1 | 1 |
| Features conferidas | 179 | 179 |

O Transcript informou que todas as features foram conferidas, todas as entradas enviadas foram invalidadas e a segunda varredura não produziu features repetidas. O resumo final marcou como aprovados Hash Unit + Controller, Controller + Flow Table, Controller + Finalizer, layout de 384 bits, vetor de features de 248 bits, handshake `fin_valid` / `fin_done`, invalidação e segunda varredura. A simulação encerrou por `$finish` em **4.231.870 ns**, no testbench (linha 768), com a mensagem **“TODOS OS TESTES FORAM CONCLUIDOS COM SUCESSO.”** A indicação `Break in Module` corresponde ao parâmetro `-onfinish stop`.

## 5. Evidências e conclusão

- **Transcript:** captura do resumo final do `run -all`, com 181 pacotes, contadores, verificações e `$finish`.
- **Wave:** captura ampliada de `clk`, `rst`, `fin_valid`, `fin_done` e `feature_vector` em hexadecimal.

**Conclusão:** a integração FIU/Hash + Controller + Flow Table + Finalizer passou no conjunto de 181 vetores reproduzido no ModelSim de Bruno. A integração com o Packet Parser permanece como etapa posterior da Semana 8.

**BRUNO_SAMUEL**
