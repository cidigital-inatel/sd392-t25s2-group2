# Falhas e correções da Semana 6 na FIU e no Hash

Projeto CI Digital Inatel, T25S2, Grupo 2. Samuel e Bruno. Revisão: 22/10/2026. Referência principal: `Semana_6.docx`, seções 2.3 e 3.

O objetivo deste registro é mostrar quais comportamentos anteriores precisaram ser alterados para o protocolo da Semana 6 e como as correções foram verificadas. As duas incompatibilidades funcionais foram reproduzidas com códigos históricos. Os RTLs atuais passaram quando receberam os mesmos estímulos.

1. **F01 Validade prolongada era tratada como entrada indevida no Hash.**

Base: `hash_unit.sv` do ZIP anexo, identificado pelo SHA-256 abaixo.

```text
2ade61d898a2ce5708d2f00aea2925927bd3059678accfee7efe11c1c97f21f3
```

O teste `tb_valid_high_hash.sv` mantém uma única chave válida por 24 clocks. O protocolo da Semana 6 exige uma captura e nenhuma repetição até observar baixo. Na versão anterior, a segunda borda com validade alta, aos 35 ns do teste de regressão, acionou `PROTOCOL_VIOLATION` porque o Hash já estava ocupado.

O comportamento anterior seguia a hipótese de pulso de um ciclo daquela versão. A incompatibilidade encontrada é com a regra de recepção da Semana 6; o teste não identificou erro nos parâmetros ou no cálculo do CRC.

Correção: acrescentar `valid_seen`, capturar somente com `in_valid && !valid_seen && capture_allowed` e testar ocupação apenas na primeira observação de um período alto. As bordas seguintes do mesmo período não representam outra entrada.

| Evidência | Resultado |
|---|---|
| `validation/regressions/hash_baseline.log` | Encerramento esperado por incompatibilidade antiga |
| `validation/regressions/hash_semana6.log` | Uma entrega com `valid` alto por 24 clocks |
| `validation/alteracoes_hash.diff` | Alteração exata entre a base e o RTL atual |
| Teste unitário completo do Hash | 186 entregas conferidas, incluindo validade prolongada |

2. **F02 A FIU anterior podia publicar repetidamente sem valid baixo.**

Base: RTL contido no ZIP público `semana4_fiu_BRUNO.zip` na revisão consultada do repositório. SHA-256 do arquivo extraído:

```text
0e7b4c2a0867648aa80bc7cf0ed5c5cb5132c1c99ff9231599a76720ad66c6cf
```

O teste `tb_valid_high_fiu.sv` mantém o mesmo registro com validade alta por 24 clocks. No teste histórico, `out_ready` é ligado em um para liberar a interface antiga. A FIU anterior pode então capturar e publicar em bordas sucessivas, produzindo mais de uma entrega para o mesmo período alto. O teste detectou a segunda entrega aos 45 ns e encerrou com `REGRESSION_VALID_HIGH_DUPLICATED`.

Essa ligação de `out_ready` existe apenas no teste do código histórico, compilado separadamente. O top da Semana 6 usa os RTLs atuais e o protocolo somente com validade.

Correção: recepção com `valid_seen`, captura atômica dos sete campos, `start` registrado e FSM que publica por um ciclo. A saída só é produzida a partir de uma captura nova.

| Evidência | Resultado |
|---|---|
| `validation/regressions/fiu_baseline.log` | Repetição antiga reproduzida |
| `validation/regressions/fiu_semana6.log` | Uma entrega com o mesmo estímulo de 24 clocks |
| `validation/alteracoes_fiu.diff` | Migração completa do RTL público consultado |
| Teste unitário completo da FIU | 186 entregas conferidas, sem duplicação |

3. **F03 A interface pública antiga da FIU incluía out_ready.**

A conferência do código mostrou `out_ready` como entrada no módulo anterior. A seção 3 da Semana 6 exige validade sem introduzir `ready`, e o diagrama indicado apresenta a ligação direta dos três campos de dados e da validade entre FIU e Hash.

Correção: a FIU atual tem dez entradas, incluindo clock, reset e validade, e quatro saídas. O `out_ready` anterior foi retirado. O Hash mantém suas 11 portas, com seis entradas e cinco saídas. O top conecta os três campos e a validade, além do clock e do reset comuns.

Esta é uma divergência identificada por inspeção da interface, e não um erro de CRC observado durante execução. A compilação do top atual e a simulação das 188 transferências FIU para Hash confirmaram a compatibilidade dos arquivos entregues. O nome e a polaridade `reset_n` foram preservados nos dois módulos e documentados para alinhamento com o sistema.

4. **F04 Intervalo da FIU isolada excedia a capacidade do Hash quando usado na integração.**

Este é um teste negativo planejado. A FIU pode receber localmente a cada três clocks; o Hash serial precisa de 16 clocks entre capturas. O teste integrado aplica duas entradas na FIU separadas por três clocks. A primeira chega normalmente ao Hash; a segunda tenta chegar enquanto ele ainda calcula.

O diagnóstico esperado e obtido foi `PROTOCOL_VIOLATION: HASH recebeu nova transferencia ocupado`, aos 95 ns do teste negativo. O arquivo `validation/integracao_negative_busy.log` registra essa execução. Os testes unitários de chegada ocupada também foram detectados.

A correção do cenário nominal é respeitar o intervalo integrado de 16 clocks, mantendo pelo menos uma borda baixa entre períodos altos de validade. O teste nominal exerceu 157 intervalos mínimos no caminho integrado e preservou todos os dados. A solução mantém a decisão de operação sem FIFO e documenta a condição que o produtor precisa cumprir.

O diagnóstico de ocupação existe apenas na simulação. No hardware, uma chegada indevida não é enfileirada nem repetida automaticamente. A interface depende da folga entre publicações e do intervalo documentado para esta versão.

5. **Confira como as correções foram validadas.**

| Grupo de testes | Resultado observado |
|---|---|
| Três simulações nominais | PASS, 558 entregas comparadas |
| Comparações de CRC no Hash e na integração | 372 índices corretos |
| Testes de validade prolongada | Uma captura por período alto; rearme após baixo |
| Três testes negativos de ocupação | Falha específica esperada em cada caso |
| Regressões antes e depois | Dois baselines falham; duas versões atuais passam |
| Cancelamento por reset no caminho integrado | Quatro cancelamentos previstos, zero resíduos |

Para reproduzir os comportamentos históricos e suas correções, execute `python3 python/run_regressions.py`. Os baselines são compilados em bibliotecas e binários separados dos RTLs atuais. A única supressão adicional nessa reprodução é `TIMESCALEMOD` no código histórico da FIU, que não declara timescale; os erros funcionais não são suprimidos.

Os resultados de referência e os testes finais não apresentaram divergência de CRC, chave ou metadados. Este registro não atribui as incompatibilidades a possíveis versões locais posteriores do Bruno; sua base está identificada pelo arquivo e pelo hash. O material está pronto para revisão e alinhamento entre os responsáveis, conforme a Semana 6.
