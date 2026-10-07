# Contrato de Interface — Hash Unit

**Projeto:** Arquitetura em FPGA para Extração de Features de Fluxos TCP/IP — CI Digital Inatel, T25S2, Grupo 2.  
**Frente:** Extração de Metadados — Samuel, Bruno e Herman.  
**Versão:** 0.2 — 6 de outubro de 2026.  
**Status:** proposta de contrato para revisão conjunta; não representa aprovação das equipes nem implementação RTL.

## 1. Objetivo e limite da Semana 3

Especificar todos os sinais das interfaces Flow Identification Unit → Hash Unit e Hash Unit → Controller, incluindo os retornos de disponibilidade, clock, reset, larguras, significados e protocolo de transferência.

A decisão arquitetural existente é utilizar CRC-16 e preservar seus 16 bits de saída como índice da Flow Table. Esta atividade registra a função da porta de índice e sua largura. A variante, os parâmetros, a ordem de processamento do CRC e sua realização em HDL não são definidos neste contrato da Semana 3.

**Revisão desta versão:** não exigir FIFO na PoC, conforme a orientação do professor Elivander relatada por Samuel. A folga entre recepção e processamento passa a ser uma premissa de integração; o protocolo `valid/ready` e todas as portas da Hash Unit são preservados.

## 2. Responsabilidade do módulo na interface

A Hash Unit recebe um registro formado por `flow_key`, `packet_length` e `timestamp`. Produz `hash_index` a partir exclusivamente da chave e entrega ao Controller o índice junto com a mesma chave, o mesmo comprimento e o mesmo timestamp.

- A chave recebida possui 104 bits e representa uma 5-tuple unidirecional.
- O índice possui 16 bits, sem redução para cinco bits.
- Comprimento e timestamp são dados associados ao pacote; não participam do hash.
- A mesma chave deve produzir o mesmo índice para a função de hash adotada, mesmo que comprimento e timestamp mudem.
- A chave completa segue até o Controller, pois índices iguais podem representar chaves diferentes.
- A Hash Unit não consulta a Flow Table nem decide HIT, MISS ou COLLISION.

O conjunto de entrada tem 200 bits de dados; o conjunto de saída tem 216 bits de dados. Validade, disponibilidade, clock e reset não integram essas somas.

## 3. Base documental e propostas

| Item | Origem | Situação |
|---|---|---|
| Chave de 104 bits, comprimento de 16 bits e índice de 16 bits | Diagrama e README | Preservados. |
| Timestamp de 80 bits | Diagrama e contrato do Controller | Referência de integração; alinhar com o Parser, cujo contrato deixa a largura aberta. |
| Aceitação pelo Controller com `in_valid && in_ready` | Contrato do Controller no repositório | Preservada; exige uma conexão de retorno para a Hash Unit, ausente no diagrama fornecido. |
| Retorno de disponibilidade à Flow Identification Unit | Proposta de protocolo desta orientação | Incluir `in_ready` na Hash Unit e conectá-lo a `out_ready` da Flow Identification Unit. |
| Operação sem exigir FIFO | Orientação do professor Elivander, relatada por Samuel em 6 de outubro de 2026 | Compatibilizar as esperas de Hash/Controller com o intervalo entre publicações do Parser; não supor capacidade de acumular uma fila de pacotes. |
| Clock comum e transferências na borda de subida | Proposta de integração | Confirmar entre equipes. |
| `reset_n` ativo baixo | Contratos do Parser e Controller | Polaridade preservada; funcionamento síncrono proposto para alinhamento. |
| Sufixos `_in` e `_out` nas portas de dados | Proposta de nomenclatura | Compatíveis com o documento da Flow Identification Unit; alinhar os nomes finais. |

## 4. Protocolos das tabelas

| Código | Definição |
|---|---|
| P0 | Clock comum; valores de transferência amostrados na borda de subida de `clk`. |
| P1 | Reset síncrono ativo baixo, proposto: uma borda com `reset_n = 0` cancela registros pendentes e reinicializa o controle. Não se contabilizam transferências durante reset. |
| P2 | Entrada com handshake: um registro completo é aceito em uma borda com `reset_n = 1`, `in_valid = 1` e `in_ready = 1`. |
| P3 | Saída com handshake: um registro completo é entregue em uma borda com `reset_n = 1`, `out_valid = 1` e `out_ready = 1`. |

As direções abaixo são relativas à Hash Unit. A aprovação de P0/P1 depende do alinhamento dos módulos. O mecanismo P2/P3 utiliza as regras de `valid/ready` em uma interface própria de registros.

## 5. Entradas

| Interface | Sinal | Direção | Largura | Descrição | Protocolo |
|---|---|---|---:|---|---|
| Sistema → Hash | `clk` | Entrada | 1 bit | Clock comum ao caminho de metadados e ao Controller. | P0 |
| Sistema → Hash | `reset_n` | Entrada | 1 bit | Reset ativo baixo; forma síncrona proposta. | P1 |
| Flow Identification → Hash | `flow_key_in[103:0]` | Entrada | 104 bits | Chave do fluxo; conectada a `flow_key_out` da Flow Identification Unit. | P2 |
| Flow Identification → Hash | `packet_length_in[15:0]` | Entrada | 16 bits | Comprimento do mesmo pacote da chave; conectado a `packet_length_out`. | P2 |
| Flow Identification → Hash | `timestamp_in[79:0]` | Entrada | 80 bits | Timestamp do mesmo pacote da chave; conectado a `timestamp_out`. | P2 |
| Flow Identification → Hash | `in_valid` | Entrada | 1 bit | O registro completo de entrada está disponível; conectado a `out_valid` da Flow Identification Unit. | P2 |
| Controller → Hash | `out_ready` | Entrada | 1 bit | Controller pode aceitar o registro completo nesta borda; conectado a `in_ready` do Controller. | P3 |

## 6. Saídas

| Interface | Sinal | Direção | Largura | Descrição | Protocolo |
|---|---|---|---:|---|---|
| Hash → Flow Identification | `in_ready` | Saída | 1 bit | Hash Unit pode aceitar e preservar um novo registro completo nesta borda; conectado a `out_ready` da Flow Identification Unit. | P2 |
| Hash → Controller | `hash_index_out[15:0]` | Saída | 16 bits | Resultado da função CRC-16 aplicada à chave do registro; conectado a `hash_index` do Controller. | P3 |
| Hash → Controller | `flow_key_out[103:0]` | Saída | 104 bits | A mesma chave associada ao índice apresentado; conectada a `flow_key` do Controller. | P3 |
| Hash → Controller | `packet_length_out[15:0]` | Saída | 16 bits | Comprimento preservado do registro correspondente; conectado a `packet_length` do Controller. | P3 |
| Hash → Controller | `timestamp_out[79:0]` | Saída | 80 bits | Timestamp preservado do registro correspondente; conectado a `timestamp` do Controller. | P3 |
| Hash → Controller | `out_valid` | Saída | 1 bit | Índice e metadados associados estão disponíveis como um conjunto; conectado a `in_valid` do Controller. | P3 |

`in_ready` informa disponibilidade da Hash Unit. `out_ready` informa disponibilidade do Controller. São sinais distintos, produzidos por módulos distintos. Não existe uma ligação direta obrigatória entre seus valores.

## 7. Regras de transferência

### 7.1. Recepção do registro

Um registro é aceito somente na borda em que `in_valid && in_ready` está ativo, com reset inativo. Todos os campos são capturados como um conjunto.

Enquanto `in_valid = 1` e `in_ready = 0`, a Flow Identification Unit preserva sua saída. A Hash Unit não contabiliza uma nova entrada nem considera o registro recebido nessa espera.

A Hash Unit só ativa `in_ready` quando possui capacidade real para aceitar e manter a associação completa do registro até sua entrega. Uma entrada aceita não pode ser descartada por indisponibilidade posterior do Controller, salvo cancelamento pelo reset do sistema.

### 7.2. Disponibilização e entrega do resultado

`out_valid` indica a disponibilidade conjunta de índice, chave, comprimento e timestamp. Não basta que apenas o índice esteja pronto.

Enquanto `out_valid = 1` e `out_ready = 0`, os quatro campos e `out_valid` permanecem estáveis. A validade não depende de o Controller ter ativado sua disponibilidade primeiro.

Na borda com `out_valid && out_ready`, o Controller aceita exatamente um registro. Depois dessa borda, a Hash Unit pode apresentar o próximo registro ou desativar a validade se não houver outro resultado disponível.

Quando uma validade está desativada, o receptor ignora os respectivos dados. Não se exige zerar esses campos inválidos.

### 7.3. Ordem, associação e ausência de duplicação

Sem reset, cada registro aceito deve originar exatamente um registro entregue, na mesma ordem de aceitação. Pacotes com a mesma chave continuam sendo registros distintos.

Uma saída entregue corresponde a uma entrada aceita anteriormente ou, caso a implementação permita transferência sem atraso, na mesma borda. Não pode existir saída entregue sem entrada correspondente.

Entrada e saída podem transferir na mesma borda somente se a implementação realmente tiver capacidade e apresentar corretamente ambos os conjuntos. O contrato não obriga essa simultaneidade. Esta versão não exige FIFO; a preservação do registro em processamento ou do resultado pendente continua necessária, conforme o protocolo.

### 7.4. Latência e capacidade de processamento

Nesta Semana 3 não é fixada uma latência de cálculo nem um intervalo entre aceitações. O consumidor usa `out_valid` para reconhecer disponibilidade e o produtor usa `in_ready` para reconhecer capacidade.

Isso não permite deixar uma entrada aceita sem resultado indefinidamente: sem reset, cada registro aceito deve ser disponibilizado após seu processamento. A espera para entrega pode persistir enquanto o Controller mantiver `out_ready = 0`.

A orientação do professor é que o processamento ocorre com folga em relação à recepção dos pacotes. Na PoC sem FIFO, o tempo de processamento e as esperas pelo Controller devem permitir a liberação do caminho antes de uma publicação que precisaria ocupar a saída da Flow Identification ainda bloqueada. Essa condição é detalhada no contrato da Flow Identification Unit.

Os limites numéricos de latência, atendimento e bloqueio serão conferidos na etapa de implementação/verificação. Esta entrega não atribui número de ciclos nem afirma uma medição de desempenho. A orientação não significa que `in_ready` ou `out_ready` sejam obrigatoriamente constantes em 1.

## 8. Exemplo temporal do protocolo

A e B representam registros completos. `h(A)` é um índice simbólico, sem cálculo CRC. O exemplo mostra a entrega de A antes da apresentação de B, coerente com a folga entre pacotes relatada pelo orientador. Os ciclos são ilustrativos, sem fixar latência.

Todos os sinais são valores antes da borda, com reset inativo.

| Borda | Entrada apresentada | `in_valid` | `in_ready` | Saída apresentada | `out_valid` | `out_ready` | Transferência na borda |
|---|---|---:|---:|---|---:|---:|---|
| E1 | A | 1 | 1 | Nenhuma válida | 0 | 1 | A aceito pela Hash Unit. |
| E2 | Nenhuma válida | 0 | 0 | Nenhuma válida | 0 | 0 | A em processamento; nenhuma transferência. |
| E3 | Nenhuma válida | 0 | 0 | `h(A)` + metadados de A | 1 | 0 | A aguarda o Controller; conjunto preservado. |
| E4 | Nenhuma válida | 0 | 0 | Mesmo conjunto de A | 1 | 1 | A entregue ao Controller. |
| E5 | Nenhuma válida | 0 | 1 | Nenhuma válida | 0 | 1 | Intervalo entre registros. |
| E6 | B | 1 | 1 | Nenhuma válida | 0 | 1 | B aceito pela Hash Unit. |

A é recebido uma vez e entregue uma vez. B é recebido somente em E6 e ainda precisa produzir sua entrega. `out_valid = 0` em E6 não comprova esvaziamento, pois B acabou de ser aceito para processamento.

A ausência de FIFO não elimina a espera demonstrada em E3: o resultado permanece válido e estável até a aceitação. Não se acumula uma fila de pacotes neste exemplo.

## 9. Reset e controles externos

Propomos reset síncrono ativo baixo, em clock comum. Uma borda com reset ativo reinicializa o controle e cancela registros pendentes. Não se contabilizam handshakes durante reset; após a borda de reset, as validades e a disponibilidade de entrada ficam desativadas durante o reset. Na retomada, a disponibilidade de entrada é apresentada conforme a capacidade real.

Um registro anterior ao reset não deve reaparecer como resultado posterior. A proposta precisa ser confirmada com o Parser, a Flow Identification Unit e o Controller.

O contrato do Controller contém `pcap_done` como entrada do sistema de verificação. Esse sinal não é entrada nem saída da Hash Unit. A integração deve evitar a finalização global enquanto houver registros pendentes na cadeia. Observar apenas `out_valid = 0`, ou apenas `in_ready = 1`, não comprova o esvaziamento de uma implementação com processamento ou retenção interna.

Não são adicionados `start`, `busy`, `done`, sinais de acesso à memória ou eventos de colisão: o protocolo de entrada e saída aqui definido comunica disponibilidade e aceitação dos registros.

## 10. Condições para conferir o contrato

As condições abaixo verificam a coerência dos sinais e das transferências. Não representam um testbench RTL executado.

| Condição | Comportamento exigido |
|---|---|
| Entrada válida com Hash indisponível | Nenhuma aceitação; produtor preserva os dados. |
| Entrada válida com Hash disponível | Uma aceitação do conjunto completo. |
| Resultado válido com Controller indisponível | Validade e quatro campos de saída estáveis. |
| Resultado válido com Controller disponível | Uma entrega do conjunto completo. |
| Mesma chave em pacotes distintos | Índice igual para a função adotada; comprimento e timestamp preservados separadamente para cada pacote. |
| Chaves diferentes com índice igual | Duas entregas com suas chaves completas; decisão de colisão permanece no Controller. |
| Validade mantida durante espera | Nenhuma duplicação de aceitação ou entrega. |
| Reset durante espera/processamento | Cancelamento do registro anterior, sem resultado residual depois do reset. |

Em um intervalo sem reset e iniciado sem registros pendentes: quantidade de entradas aceitas = quantidade de saídas entregues + quantidade de registros ainda pendentes na Hash Unit. A verificação deve comparar também a ordem e os metadados associados.

## 11. Resumo das portas

Entradas:

```text
clk
reset_n
flow_key_in[103:0]
packet_length_in[15:0]
timestamp_in[79:0]
in_valid
out_ready
```

Saídas:

```text
in_ready
hash_index_out[15:0]
flow_key_out[103:0]
packet_length_out[15:0]
timestamp_out[79:0]
out_valid
```

## 12. Alinhamentos necessários na Semana 3

| Tema | Ação de alinhamento |
|---|---|
| Retorno à Flow Identification Unit | Incorporar `Hash.in_ready → FlowIdentification.out_ready` ao diagrama e aos contratos. |
| Retorno do Controller | Incorporar `Controller.in_ready → Hash.out_ready`, conforme contrato existente do Controller. |
| Timestamp | Confirmar 80 bits no Parser, nos módulos de metadados e no Controller; registrar formato e unidade com verificação/TSU e features. |
| Comprimento | Registrar qual comprimento o Parser informa para a atualização de `byte_count`; este módulo preserva o valor. |
| Clock/reset | Aprovar clock comum, borda de subida e proposta de reset síncrono ativo baixo. |
| Nomes | Confirmar os nomes das portas e as correspondências entre módulos. |
| Operação sem FIFO | Compatibilizar as esperas pelo Controller com o intervalo entre publicações do Parser, conforme a orientação do professor e o contrato da Flow Identification. |
| Fim do PCAP | Esperar a conclusão dos registros pendentes antes da finalização global, mesmo sem fila de vários registros. |

A especificação das interfaces está documentada nesta proposta. A aprovação conjunta desses itens permanece necessária para o contrato final. A definição detalhada e a implementação do CRC pertencem à etapa correspondente do projeto.

## 13. Fontes

- Orientação do professor Elivander, relatada por Samuel em 6 de outubro de 2026: FIFO provavelmente dispensável pela folga entre recepção e processamento. Premissa qualitativa, não medição executada nesta entrega.
- `Semana 3.docx(1).pdf`: escopo e tabela de contrato exigida.
- `packet_parser_interface(1).md`: campos publicados pelo Parser e polaridade de reset.
- `Interfaces(1).pdf`: conexões e larguras dos dados entre módulos.
- [Flow Identification Unit — contrato desta orientação](./flow_identification_interface.md).
- [README do projeto](https://github.com/cidigital-inatel/sd392-t25s2-group2/blob/main/README.md): CRC-16, índice de 16 bits e comparação da chave para distinguir fluxos.
- [Controller_interface.md](https://github.com/cidigital-inatel/sd392-t25s2-group2/blob/main/Especifica%C3%A7%C3%A3o/Extracao%20de%20Features/Controller_interface.md), consultado em 5 de outubro de 2026, blob `08844112774ba37858c23ca3d259743e5b96c081`: portas da frente de features e transferência por `in_valid && in_ready`.
- [AMD UG1483 — AXI4-Stream Support in Model Composer](https://docs.amd.com/r/en-US/ug1483-model-composer-sys-gen-user-guide/AXI4-Stream-Support-in-Model-Composer): referência para handshake e preservação de dados; não se declara aqui uma interface AXI4-Stream completa.
