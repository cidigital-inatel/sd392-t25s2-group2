# Semana 7 — Simulação integrada FIU + Hash + Controller no ModelSim

**Responsável pela simulação e pelas evidências:** Bruno Coura  
**Data:** 02/11/2026  
**Escopo:** atividade 2.4 (integração Hash Unit + Controller), com verificação do caminho Controller + Flow Table + Flow Finalizer.

## 1. Objetivo

Reproduzir no ModelSim o teste integrado com entradas conhecidas, verificar a captura de `hash_index`, `flow_key` e metadados pelo Controller e conferir os resultados de MISS, HIT e COLLISION. A varredura também verifica os vetores de features produzidos pelo Finalizer.

## 2. Arquivos e preparação

| Grupo | Arquivos usados |
|---|---|
| RTL | `fiu_hash_top.sv`, `flow_identification_unit.sv`, `hash_unit.sv`, `controller_base.sv`, `flow_table.sv`, `top_extracao_features_entrada.sv`, `flow_finalizer.sv` (versão atualizada por Fábio) |
| Testbench | `tb_top_extracao_features_com_entrada.sv` |
| Vetores | `hash_vectors.mem` na pasta do projeto, acessível a `$readmemh` |

O arquivo `flow_finalizer.sv` define o módulo `flow_finalizer_v3`. A versão antiga `code_flow_finalizer_v3.sv` foi retirada da lista de compilação, evitando definições duplicadas. O topo já havia sido adaptado para compilar no ModelSim, com declarações explícitas das portas de entrada. O projeto usou oito arquivos SystemVerilog e apresentou **0 falhas de compilação**.

## 3. Execução no ModelSim

1. Abrir o projeto `semana7_fiu_hash_controller_projeto`.
2. Selecionar **Compile > Compile All** e confirmar `8 compiles, 0 failed with no errors`.
3. Carregar a simulação com `vsim -onfinish stop work.tb_top_extracao_features_com_entrada`.
4. Digitar `run -all` no Transcript. Para uma nova execução após alterar o RTL, encerrar a simulação anterior com `quit -sim`, carregar novamente o testbench e executar `run -all`.
5. Para obter a Wave, adicionar os sinais antes de executar o teste; após `restart -f`, executar `run -all` e usar **Zoom Full**. O teste foi repetido com os sinais registrados.

O aviso `GetModuleFileName: Não foi possível encontrar o módulo especificado` apareceu no Transcript após `restart -f`. O testbench prosseguiu e terminou com todas as verificações aprovadas; convém registrar o aviso, sem tratá-lo como falha do teste.

## 4. Resultado observado

| Verificação | Esperado | Obtido |
|---|---:|---:|
| Pacotes processados | 181 | 181 |
| MISS | 179 | 179 |
| HIT | 1 | 1 |
| COLLISION | 1 | 1 |
| Features conferidas | 179 | 179 |
| Entradas enviadas | Invalidadas | Invalidadas |
| Segunda varredura | 0 features repetidas | 0 features repetidas |

O Transcript registra `PASSOU: todas as features foram conferidas`, `PASSOU: todas as entradas enviadas foram invalidadas`, `PASSOU: segunda varredura sem features repetidas` e `TODOS OS TESTES FORAM CONCLUIDOS COM SUCESSO`. A simulação terminou em **4.231.870 ns** (`$finish`, linha 704 do testbench). O `Break in Module` após `$finish` decorre da opção `-onfinish stop`.

O vetor de saída conferido possui **248 bits**: `flow_key` (104), `packet_count` (32), `byte_count` (32) e `duration` (80). O registro enviado ao Finalizer possui 384 bits.

## 5. Evidências

- **Transcript:** captura `image(20261102-150533).png`, com os totais, as verificações aprovadas e o encerramento.
- **Wave geral:** captura `image(20261102-164239).png`, com `in_valid`, `hash_valid`, `pcap_done`, `fin_valid`, `fin_done`, `flow_entry` e `feature_vector`.
- **Wave ampliada:** captura `image(20261102-164818).png`, com cursor em `fin_done = 1` e `fin_valid = 1`, exibindo o registro e o vetor de features em hexadecimal.

As formas de onda ilustram a sequência dos sinais. A comparação numérica dos 179 vetores e a aprovação final são verificações do testbench registradas no Transcript. As capturas originais devem acompanhar a documentação no repositório se forem usadas como evidência visual.

## 6. Conclusão

**A simulação integrada foi aprovada no ModelSim com o Finalizer atualizado.** Os 181 pacotes foram processados, a classificação coincidiu com o modelo de referência e os 179 vetores de features foram conferidos. A invalidação das entradas e a ausência de reenvio na segunda varredura também passaram. O resultado valida os cenários e intervalos exercitados por este testbench; a documentação da Elaine recomenda ampliar, em etapa futura, os casos de HIT, COLLISION, duração não nula e rajadas de pacotes.
