# Semana 5 - Simulação da Hash Unit no ModelSim

**Projeto:** CI Digital Inatel - TCC do Grupo 2  
**Responsável pelo RTL, testbench e vetores:** Samuel  
**Responsável pela execução e registro da simulação no ModelSim:** Bruno  
**Data da simulação documentada:** 15/10/2026

## 1. Objetivo

Validar isoladamente a Hash Unit de Samuel no ModelSim, comparando o CRC16 e os metadados produzidos com os valores esperados pelo testbench. Este registro documenta a atividade de simulação realizada na Semana 5. O pacote original de implementação, preparado por Samuel na Semana 4, preserva sua autoria.

## 2. Arquivos usados

| Arquivo | Finalidade |
|---|---|
| `hash_unit.sv` | RTL da Hash Unit. |
| `tb_hash_unit.sv` | Testbench que aplica os casos e verifica os resultados. |
| `hash_vectors.mem` | Vetores de referência lidos durante a execução. |

Os dois arquivos `.sv` são compilados. O arquivo `.mem` não é compilado: o testbench o lê durante a simulação. Os vetores são dados sintéticos de referência; não representam uma captura real da saída do Packet Parser.

## 3. Procedimento no ModelSim

1. Colocar os arquivos do RTL e do testbench em `C:\semana4_hash_unit_arquivos` e manter os vetores em `C:\semana4_hash_unit_arquivos\tb\hash_vectors.mem`.
2. Criar ou abrir o projeto do ModelSim e compilar `hash_unit.sv` e `tb_hash_unit.sv` como SystemVerilog. A compilação registrada terminou com **0 erros e 0 avisos**.
3. No Transcript, carregar o testbench com:

   ```tcl
   set vetores C:/semana4_hash_unit_arquivos/tb/hash_vectors.mem
   vsim work.tb_hash_unit +VECTORS=$vetores
   ```

4. Adicionar à janela Wave os sinais de interesse, por exemplo `clk`, `reset_n`, entradas, sinais `valid`/`ready`, `hash_index_out` e metadados de saída. Para visualizar os valores da chave e do índice, selecionar radix hexadecimal.
5. Executar `run -all`. Para conservar a janela de formas de onda ao término do testbench, usar `vsim -onfinish stop` ao carregar a simulação em uma nova sessão.
6. Conferir o Transcript e posicionar o cursor da Wave em uma saída válida para comparar entrada, índice e metadados associados.

> **Nota:** Os caminhos acima reproduzem a organização usada na execução de 15/10/2026. Se os arquivos forem movidos, atualizar o caminho informado em `+VECTORS`.

## 4. Resultado registrado

O Transcript da execução de 15/10/2026 registrou:

```text
Errors: 0, Warnings: 0
PASS: latencia de 13 atualizacoes e saida preservada na espera.
PASS: reset durante calculo, sem resultado residual.
PASS: reset com resultado em espera, sem entrega residual.
PASS: 181 vetores golden, CRC e todos os metadados conferidos.
SUMMARY accepted=184 delivered=182 reset_cancelled=2 pending=0
SUMMARY output_stability_checks=272 input_wait_cycles=2785
PASS: tb_hash_unit concluido sem divergencias.
```

A diferença entre os registros aceitos e entregues corresponde aos dois cancelamentos por reset reportados pelo próprio teste: `184 - 2 = 182`. O testbench informou que os 181 vetores de referência passaram, incluindo CRC e metadados. O término por `$finish` é esperado após a conclusão do teste.

## 5. Conclusão

A simulação isolada da Hash Unit no ModelSim foi concluída sem divergências nos casos exercitados pelo testbench. O resultado sustenta a validação funcional do CRC16 e da associação dos metadados para os 181 vetores aplicados, além dos cenários de latência, espera e reset registrados. Esta evidência não substitui o teste da ligação com a FIU, com o Packet Parser ou com o Controller.

**Sugestão de nome para o pacote de evidências:** `semana5_hash_unit_simulacao_BRUNO.zip`. Dentro dele, manter a atribuição de Samuel nos arquivos de implementação e incluir as capturas do Transcript e da Wave feitas por Bruno.
