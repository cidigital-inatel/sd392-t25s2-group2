# Semana 6 - Simulação FIU + Hash no ModelSim

**Responsável pela reprodução no ModelSim:** Bruno Coura  
**Data:** 25/10/2026  
**Base dos códigos e vetores:** pacote `semana6_fiu_hash_SAMUEL.zip`, preparado por Samuel.

## 1. Objetivo e alcance

Reproduzir no ModelSim o teste de integração da Flow Identification Unit (FIU) com a Hash Unit, conferir os resultados no Transcript e observar um caso conhecido na janela Wave. Os estímulos são metadados simulados pela testbench. Esta execução não testa a ligação física com o Packet Parser ou o Controller.

## 2. Preparação dos arquivos

No computador usado para a simulação, foram criadas estas pastas:

- `C:\semana6_fiu_hash_arquivos`: conteúdo extraído do ZIP do Samuel, inclusive as subpastas `rtl` e `tb`.
- `C:\semana6_fiu_hash_projeto`: projeto do ModelSim e arquivos CSV gerados na execução.

O arquivo `tb/hash_vectors.mem` precisa permanecer acessível no caminho indicado pelo parâmetro `+VECTORS`. Ele é lido pela simulação; não deve ser compilado como código SystemVerilog.

No projeto do ModelSim, adicionar e compilar os cinco arquivos abaixo nesta ordem:

1. `C:\semana6_fiu_hash_arquivos\rtl\flow_identification_unit.sv`
2. `C:\semana6_fiu_hash_arquivos\rtl\hash_unit.sv`
3. `C:\semana6_fiu_hash_arquivos\rtl\fiu_hash_top.sv`
4. `C:\semana6_fiu_hash_arquivos\tb\metadata_testbench.sv`
5. `C:\semana6_fiu_hash_arquivos\tb\tb_fiu_hash_integration.sv`

Selecionar **Compile > Compile All**. Nesta reprodução, os cinco arquivos compilaram sem falhas.

## 3. Carregamento e execução

Na janela **Transcript**, executar o comando abaixo em uma única linha:

```tcl
vsim -onfinish stop work.tb_fiu_hash_integration +VECTORS=C:/semana6_fiu_hash_arquivos/tb/hash_vectors.mem +COUNT=181 +RESULTS=C:/semana6_fiu_hash_projeto/integracao_obtidos.csv +STAGES=C:/semana6_fiu_hash_projeto/integracao_transferencias.csv
```

O comando pressupõe a biblioteca `work` do projeto. Se as pastas estiverem em outro local, atualizar os caminhos. Em seguida:

```tcl
add wave -r /tb_fiu_hash_integration/tb/*
run -all
```

O primeiro comando adiciona os sinais da testbench à Wave; o segundo executa a simulação até o fim. Com `-onfinish stop`, a mensagem final `Break in NamedBegin` após `$finish` é esperada e não representa falha quando o relatório anterior indica `PASS`.

## 4. Conferência do Transcript

Na execução de 25/10/2026, o Transcript registrou:

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

Os 181 vetores da coleção foram conferidos. As 186 entregas incluem cinco operações adicionais de teste. A conta das entradas fecha em `190 = 186 entregues + 4 canceladas por reset + 0 pendentes`. As 188 transferências da FIU correspondem às 188 capturas do Hash. Esses contadores são do teste integrado, não de uma integração com o Parser.

## 5. Conferência da Wave

Após `run -all`, aproximar o início da execução, por exemplo com **Wave > Zoom > Zoom Range**, de `0 ns` a `250 ns`. Manter visíveis os sinais:

| Grupo | Sinais |
|---|---|
| Controle | `clk`, `reset_n`, `in_valid`, `fiu_valid`, `out_valid` |
| Resultado | `hash_index_out`, `flow_key_out`, `packet_length_out`, `timestamp_out` |

Exibir os barramentos numéricos em hexadecimal. Posicionar o cursor em um pulso de `out_valid = 1`. Para o primeiro caso conhecido (`tcp_exemplo_FI`), a captura apresentou:

| Sinal | Valor observado e esperado |
|---|---|
| `flow_key_out` | `C0A8010AC0A80114C35001BB06` |
| `packet_length_out` | `003C` (60 bytes) |
| `timestamp_out` | `8000000000000000007B` |
| `hash_index_out` | `B511` (CRC16) |

Os valores anteriores só devem ser interpretados como resultado de uma transação no instante em que `out_valid` está ativo. Outros valores que apareçam nos barramentos fora da validade não constituem uma entrega.

## 6. Arquivos gerados e evidências

- `C:\semana6_fiu_hash_projeto\integracao_obtidos.csv`: resultados publicados, conforme `+RESULTS`.
- `C:\semana6_fiu_hash_projeto\integracao_transferencias.csv`: registros de transferência FIU para Hash, conforme `+STAGES`.
- Captura do **Transcript** com o `PASS` final e os contadores.
- Captura da **Wave** com `out_valid`, dados e índice legíveis no cursor.

Para compartilhar o pacote, incluir a versão exata dos cinco arquivos `.sv`, `hash_vectors.mem`, os CSVs gerados e as capturas. Os arquivos CSV devem ser abertos para conferência antes de afirmar qualquer comparação individual além do que o Transcript e a Wave já mostram.

## 7. Conclusão

A simulação integrada FIU + Hash no ModelSim terminou sem divergências: os 181 vetores foram conferidos automaticamente, os testes extras de validade e reset passaram, e o caso observado na Wave apresentou chave, comprimento, timestamp e CRC16 esperados enquanto `out_valid = 1`. A ligação com o Packet Parser do Herman e a adoção da versão final dos RTLs pelo grupo são etapas de integração posteriores.
