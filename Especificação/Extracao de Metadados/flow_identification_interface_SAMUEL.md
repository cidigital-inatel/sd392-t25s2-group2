# Contrato de Interface - Flow Identification Unit

**Projeto:** Arquitetura em FPGA para Extração de Features de Fluxos TCP/IP - CI Digital Inatel, T25S2, Grupo 2.  
**Frente:** Extração de Metadados - Samuel, Bruno e Herman.  
**Versão:** 0.2 - 5 de outubro de 2026.  
**Status:** proposta para revisão e alinhamento entre equipes. Não constitui contrato aprovado nem evidência de implementação RTL.

Este documento especifica as portas e o comportamento temporal propostos para a Flow Identification Unit. Segue o formato de contrato solicitado na Semana 3 e utiliza como referência a interface do Packet Parser elaborada por Herman e o diagrama de interfaces fornecido pelo grupo.

**Limite desta entrega:** sinais, larguras, significados, conexões e protocolo de transferência. A organização interna da memória da FIFO, o algoritmo CRC e a implementação RTL não são definidos nesta Semana 3. A retenção dos registros e o comportamento de overflow abaixo são condições propostas para o contrato externo.

## 1. Definições existentes e propostas desta versão

| Item | Base documental | Tratamento nesta versão |
|---|---|---|
| Fluxos unidirecionais e 5-tuple | README | Preservados. Origem e destino não são ordenados nem trocados. |
| IPs de 32 bits, portas de 16 bits e protocolo de 8 bits | Contrato do Parser e README | Preservados; chave total de 104 bits. |
| Comprimento de 16 bits | Contrato do Parser e diagrama | Preservado como informação associada ao pacote. |
| Timestamp | Contrato do Parser deixa a largura aberta; diagrama e Controller indicam 80 bits | 80 bits adotados nesta proposta de integração; formato e unidade precisam ser alinhados. |
| Validade na saída do Parser, sem retorno de disponibilidade | Contrato do Parser | Proposta de uma publicação por borda com validade ativa. |
| `reset_n` ativo em nível baixo | Contratos do Parser e Controller | Polaridade preservada; reset síncrono proposto nesta versão. |
| Aceitação pelo Controller com `in_valid && in_ready` | Contrato do Controller no repositório | Referência para propagar disponibilidade pela Hash Unit. |
| FIFO dentro da Flow Identification Unit | Proposta desta orientação | Requer alinhamento; profundidade ainda precisa de dimensionamento. |
| `out_ready` e `overflow_event` da Flow Identification Unit | Propostas desta orientação | Novas conexões que precisam ser incorporadas ao diagrama e aos contratos correspondentes. |

## 2. Responsabilidade funcional

A Flow Identification Unit recebe do Packet Parser a 5-tuple, o comprimento e o timestamp de um pacote. Forma uma chave de 104 bits, preserva as demais informações e disponibiliza o registro completo para a Hash Unit, na ordem de chegada.

Nesta proposta, uma FIFO interna permite armazenar registros enquanto a Hash Unit estiver indisponível. A unidade recebe publicações do Parser sem sinal de retorno de disponibilidade e entrega registros para a Hash Unit por handshake `valid/ready`.

O cálculo do CRC, a consulta da Flow Table, a detecção de colisões e a atualização das features pertencem aos módulos seguintes. A validação de Ethernet/IPv4/TCP/UDP e a verificação final do quadro permanecem sob responsabilidade do Parser.

O timestamp e o comprimento são encaminhados sem alteração e não fazem parte da chave de fluxo.

## 3. Interfaces identificadas

1. Sistema -> Flow Identification Unit: clock e reset.
2. Packet Parser -> Flow Identification Unit: campos e validade de uma publicação.
3. Flow Identification Unit -> Hash Unit: registro completo e validade da saída.
4. Hash Unit -> Flow Identification Unit: disponibilidade para aceitar a saída.
5. Flow Identification Unit -> sistema de controle/verificação: evento de descarte por falta de capacidade.

Todas as direções das tabelas seguintes são relativas à Flow Identification Unit. Os sufixos `_in` e `_out` indicam a direção da porta de dados. Os nomes são propostos para este módulo, sem renomear as portas existentes do Parser.

## 4. Protocolos utilizados nas tabelas

| Código | Protocolo |
|---|---|
| P0 | Clock comum ao Parser, Flow Identification Unit, Hash Unit e Controller; eventos de transferência amostrados na borda de subida. |
| P1 | Reset síncrono ativo baixo: uma borda com `reset_n = 0` limpa o estado de ocupação e os eventos, com prioridade sobre entradas e saídas. |
| P2 | Publicação sem retorno de disponibilidade: em cada borda com `reset_n = 1` e `in_valid = 1`, os campos de entrada representam exatamente um novo registro. |
| P3 | Handshake de saída: o registro é aceito pela Hash Unit em uma borda com `reset_n = 1`, `out_valid = 1` e `out_ready = 1`. |
| P4 | Evento registrado por ciclo: depois de uma borda em que um novo registro foi descartado por falta de espaço, `overflow_event = 1` durante o ciclo seguinte. |

P0 e a forma síncrona de P1 precisam ser alinhados com os demais módulos. A polaridade ativa baixa já aparece nos contratos de referência.

## 5. Entradas

| Interface | Sinal | Direção | Largura | Descrição | Protocolo |
|---|---|---|---:|---|---|
| Sistema -> Flow Identification | `clk` | Entrada | 1 bit | Clock comum; define a borda de captura e transferência. | P0 |
| Sistema -> Flow Identification | `reset_n` | Entrada | 1 bit | Reset ativo baixo, síncrono na proposta desta versão. | P1 |
| Parser -> Flow Identification | `src_ip_in[31:0]` | Entrada | 32 bits | IPv4 de origem, conectado a `src_ip` do Parser. | P2 |
| Parser -> Flow Identification | `dst_ip_in[31:0]` | Entrada | 32 bits | IPv4 de destino, conectado a `dst_ip` do Parser. | P2 |
| Parser -> Flow Identification | `src_port_in[15:0]` | Entrada | 16 bits | Porta TCP/UDP de origem, conectada a `src_port` do Parser. | P2 |
| Parser -> Flow Identification | `dst_port_in[15:0]` | Entrada | 16 bits | Porta TCP/UDP de destino, conectada a `dst_port` do Parser. | P2 |
| Parser -> Flow Identification | `protocol_in[7:0]` | Entrada | 8 bits | Campo Protocol do IPv4, conectado a `protocol` do Parser. | P2 |
| Parser -> Flow Identification | `packet_length_in[15:0]` | Entrada | 16 bits | Comprimento associado ao pacote, conectado a `packet_length` do Parser. Sua definição de contagem de bytes deve ser alinhada entre Parser e Controller. | P2 |
| Parser -> Flow Identification | `timestamp_in[79:0]` | Entrada | 80 bits | Timestamp do pacote, conectado a `timestamp` de saída do Parser. Largura de integração proposta. | P2 |
| Parser -> Flow Identification | `in_valid` | Entrada | 1 bit | Publicação de um novo registro; conectado a `metadata_valid` do Parser. | P2 |
| Hash -> Flow Identification | `out_ready` | Entrada | 1 bit | Hash Unit pode aceitar o registro de saída nesta borda; conectado a `in_ready` da Hash Unit. | P3 |

**Atenção à nomenclatura:** `timestamp_in` desta unidade recebe a saída `timestamp` do Parser. Não é uma ligação direta à porta `timestamp_in` do Parser, que recebe o tempo do ambiente de verificação/TSU.

## 6. Saídas

| Interface | Sinal | Direção | Largura | Descrição | Protocolo |
|---|---|---|---:|---|---|
| Flow Identification -> Hash | `flow_key_out[103:0]` | Saída | 104 bits | Chave unidirecional formada pela 5-tuple; conectada a `flow_key_in` proposto da Hash Unit. | P3 |
| Flow Identification -> Hash | `packet_length_out[15:0]` | Saída | 16 bits | Comprimento do mesmo pacote da chave apresentada; conectado a `packet_length_in` proposto da Hash Unit. | P3 |
| Flow Identification -> Hash | `timestamp_out[79:0]` | Saída | 80 bits | Timestamp do mesmo pacote da chave apresentada; conectado a `timestamp_in` proposto da Hash Unit. | P3 |
| Flow Identification -> Hash | `out_valid` | Saída | 1 bit | O registro completo na saída está disponível; conectado a `in_valid` da Hash Unit. | P3 |
| Flow Identification -> controle/verificação | `overflow_event` | Saída | 1 bit | Indica descarte integral de uma publicação por falta de espaço; não representa colisão de hash. | P4 |

Não há `in_ready` de saída para o Parser nesta proposta. Portanto, a unidade não pode solicitar ao Parser que suspenda suas publicações. `out_ready` controla exclusivamente a retirada de registros pela Hash Unit.

## 7. Composição e representação da chave

A concatenação proposta segue a ordem apresentada no README:

```systemverilog
flow_key = {src_ip_in, dst_ip_in, src_port_in, dst_port_in, protocol_in};
```

| Campo | Largura | Posição em `flow_key[103:0]` |
|---|---:|---|
| `src_ip_in` | 32 bits | `[103:72]` |
| `dst_ip_in` | 32 bits | `[71:40]` |
| `src_port_in` | 16 bits | `[39:24]` |
| `dst_port_in` | 16 bits | `[23:8]` |
| `protocol_in` | 8 bits | `[7:0]` |

Os campos são vetores sem sinal. Propomos que o Parser apresente o valor numérico convencional dos IPs e das portas: por exemplo, `192.168.1.10` corresponde a `32'hC0A8010A`, e a porta decimal `50000` a `16'hC350`. A Flow Identification Unit concatena esses vetores sem inverter bytes ou bits. Essa representação deve ser confirmada com o Parser e o modelo de referência.

Exemplo de referência para a composição da chave:

```systemverilog
src_ip_in   = 32'hC0A8010A; // 192.168.1.10
dst_ip_in   = 32'hC0A80114; // 192.168.1.20
src_port_in = 16'hC350;     // 50000
dst_port_in = 16'h01BB;     // 443
protocol_in = 8'h06;        // TCP

flow_key = 104'hC0A8010AC0A80114C35001BB06;
```

O exemplo confere a composição da chave, sem definir um resultado CRC. A ordem de processamento de bits/bytes pelo CRC pertence à etapa de especificação do algoritmo. O [contrato da Hash Unit da Semana 3](./hash_unit_interface.md) trata das portas e do protocolo de transferência.

Regras funcionais:

- A mesma 5-tuple deve produzir a mesma chave, independentemente do comprimento e do timestamp.
- Trocar origem e destino troca a chave, salvo quando os campos trocados forem iguais.
- Campos numericamente distintos produzem chaves distintas por esta concatenação; a possibilidade de colisão aparece posteriormente na função hash.
- Repetir uma chave em dois pacotes não autoriza remover um deles da fila. Cada publicação representa um pacote que precisa contribuir para as estatísticas.

## 8. Registro da FIFO e capacidade

A proposta retém um registro lógico com 104 bits de chave, 16 bits de comprimento e 80 bits de timestamp, totalizando 200 bits de dados por registro. A organização física ou o posicionamento desses campos dentro da memória da FIFO será tratado na implementação.

`valid` é uma informação de controle associada à ocupação da fila; não integra esses 200 bits de dados. A capacidade lógica `FIFO_DEPTH` é um inteiro positivo e inclui todos os registros retidos nesta unidade, inclusive o registro apresentado na saída. A ocupação deve permanecer entre zero e `FIFO_DEPTH`.

Não foi escolhido um valor de `FIFO_DEPTH`, porque os documentos de referência não estabelecem todos os limites necessários. Para dimensionar a fila, devem ser conhecidos:

- o intervalo mínimo e as rajadas de publicações do Parser;
- a capacidade de aceitação da Hash Unit, incluindo os períodos em que aguarda o Controller;
- a duração máxima dos bloqueios e a política de perdas aceitável para a PoC.

Em um intervalo sem reset, para uma execução que se pretende sem perdas e iniciada com fila vazia, a profundidade deve cobrir o máximo de registros publicados menos registros já aceitos pela Hash Unit. A análise deve considerar também o período de esvaziamento após o último pacote.

A fila suporta funcionalmente uma entrada e uma saída por borda, inclusive simultaneamente. Isso não afirma que a Hash Unit ou o Controller consigam processar um pacote por ciclo. Uma taxa média de chegada permanentemente maior que a taxa de atendimento produz overflow em qualquer fila finita.

## 9. Regras de publicação, aceitação e overflow

### 9.1. Publicação do Parser

Com reset inativo, cada borda com `in_valid = 1` publica um novo registro. Os sete campos de dados devem estar estáveis antes dessa borda, com os requisitos de temporização do sistema.

Publicações em bordas consecutivas são permitidas. Não se utiliza detector de borda de subida de `in_valid`. Uma publicação deve ocupar exatamente uma borda por pacote; manter a mesma publicação válida em várias bordas conta como repetição de pacote.

Com `in_valid = 0`, os dados de entrada são ignorados. A Flow Identification Unit não interpreta `TVALID`, `TLAST` ou `TUSER`; recebe a validade já consolidada pelo Parser.

### 9.2. Aceitação pela Hash Unit

Quando a fila tem registros, a saída apresenta o mais antigo e `out_valid = 1`. Esta ativação não depende de `out_ready`.

Enquanto `out_valid = 1` e `out_ready = 0`, a chave, o comprimento, o timestamp e a validade permanecem estáveis. Novas publicações podem ocupar outras posições livres, mas não podem substituir a saída pendente.

Uma borda com ambos ativos retira exatamente um registro, capturado pela Hash Unit a partir dos valores existentes antes da borda. Depois da borda, a unidade pode apresentar o registro seguinte ou desativar `out_valid` se ficou vazia. Não é obrigatório inserir um ciclo com `out_valid = 0` entre duas transferências.

### 9.3. Entrada e saída simultâneas

Para esta proposta, a fila permite retirar o registro antigo e armazenar o novo na mesma borda, mesmo quando estava cheia. O receptor captura a saída antiga antes da atualização; o novo registro é colocado no fim da ordem lógica.

Não há passagem direta de uma nova publicação para a Hash Unit quando a fila estava vazia antes da borda. Uma publicação armazenada em uma borda E pode ser apresentada durante o ciclo seguinte e aceita, no mínimo, na borda E+1. Dados e validade devem estar alinhados nessa primeira apresentação.

Uma realização em memória que introduza outra latência visível exige revisão desta regra antes da implementação; não se deve ativar a validade antes da disponibilidade dos dados.

### 9.4. Fila cheia e evento de overflow

Se a fila estiver cheia e não houver retirada na mesma borda, uma nova publicação é descartada integralmente. Registros já armazenados, sua ordem e a saída pendente são preservados.

`overflow_event` é registrado: vale 1 durante o ciclo após a borda de descarte e volta a zero após uma borda sem descarte. Descartes em bordas consecutivas mantêm o sinal ativo por ciclos consecutivos. O sinal não é uma flag permanente e não solicita repetição ao Parser.

Overflow desta fila é diferente de colisão entre chaves na Flow Table. São eventos produzidos em etapas distintas, por causas distintas.

Essas regras descrevem o comportamento externo da fila. O controle interno de ocupação, os ponteiros e a lógica de armazenamento serão definidos na etapa de implementação. Durante reset, não se contabilizam transferências; depois da borda de reset, a fila está vazia e a validade de saída está desativada.

## 10. Exemplo temporal

Neste exemplo didático, `FIFO_DEPTH = 2`. O valor serve somente para demonstrar as regras e não é uma escolha de dimensionamento. A, B, C e D representam registros completos, com chave, comprimento e timestamp.

Os sinais de entrada e saída são os valores antes da borda. A fila e o evento nas duas últimas colunas são os valores depois da borda.

| Borda | Publicação do Parser | Saída antes da borda | `out_ready` | Ação na borda | Fila após a borda | `overflow_event` após a borda |
|---|---|---|---:|---|---|---:|
| E0 | Ignorada por reset | Sem transferência | 0 | Reset | Vazia | 0 |
| E1 | A, `in_valid = 1` | Sem registro válido | 0 | Armazenar A | A | 0 |
| E2 | B, `in_valid = 1` | A, `out_valid = 1` | 0 | Armazenar B; preservar A | A, B | 0 |
| E3 | C, `in_valid = 1` | A, `out_valid = 1` | 0 | Descartar C: fila cheia | A, B | 1 |
| E4 | D, `in_valid = 1` | A, `out_valid = 1` | 1 | Entregar A e armazenar D | B, D | 0 |
| E5 | Nenhuma, `in_valid = 0` | B, `out_valid = 1` | 1 | Entregar B | D | 0 |
| E6 | Nenhuma, `in_valid = 0` | D, `out_valid = 1` | 0 | Aguardar, preservando D | D | 0 |
| E7 | Nenhuma, `in_valid = 0` | D, `out_valid = 1` | 1 | Entregar D | Vazia | 0 |
| E8 | Nenhuma, `in_valid = 0` | Sem registro válido | 1 | Nenhuma transferência | Vazia | 0 |

A ordem entregue é A, B, D. C foi a única publicação descartada e o descarte foi sinalizado. A não foi transferido em E2/E3, pois a Hash Unit não estava disponível.

## 11. Reset e delimitação do processamento

Nesta versão, propomos reset síncrono ativo baixo. Uma borda com `reset_n = 0` esvazia a fila e limpa `overflow_event`, com prioridade sobre qualquer evento de entrada ou saída. Registros anteriores ao reset não podem reaparecer depois da retomada.

Não há exigência de valor dos campos de saída quando `out_valid = 0`. Eles não devem ser utilizados pelo receptor.

A forma síncrona de reset e o uso de clock comum devem ser confirmados com o Parser e a Hash Unit. Sinais provenientes de outro domínio de clock não podem ser ligados diretamente sob este contrato.

Esta unidade não recebe nem gera `pcap_done`. A integração do sistema de verificação deve esperar a entrega dos registros pendentes na fila, na Hash Unit e no Controller antes de iniciar a finalização global. A fila estar vazia, isoladamente, não demonstra que o último registro já foi processado pelo Controller.

## 12. Critérios de verificação

Os itens abaixo são condições externas para conferir o contrato. A existência desta lista não significa que o RTL tenha sido implementado ou validado.

| Cenário | Resultado esperado |
|---|---|
| Chave com campos do exemplo da seção 7 | Exatamente `104'hC0A8010AC0A80114C35001BB06`. |
| Mesma 5-tuple, comprimentos/timestamps diferentes | Mesma chave; registros separados, preservando os dados de cada pacote. |
| Inversão de origem/destino do exemplo | Chave diferente, com as posições de origem/destino trocadas. |
| `in_valid = 0` com dados variando | Nenhum armazenamento nem overflow. |
| Publicações consecutivas, havendo capacidade | Um armazenamento por borda, na mesma ordem. |
| `out_valid = 1` e `out_ready = 0` por várias bordas | Dados e validade estáveis; nenhuma retirada. |
| `out_valid = 1` e `out_ready = 1` | Exatamente uma retirada por borda. |
| Fila cheia com retirada e publicação simultâneas | Aceitar a publicação; entregar a saída antiga; ocupação permanece no limite; sem overflow. |
| Fila cheia sem retirada, com publicação | Descartar somente a nova publicação; evento registrado; fila preservada. |
| Descartes consecutivos | `overflow_event` ativo por ciclos consecutivos, sem confundi-lo com um único descarte. |
| Reset com registros pendentes | Esvaziamento e limpeza do evento; nenhum registro anterior reaparece. |
| Primeira publicação em fila vazia com `out_ready = 1` | Armazenamento nessa borda; primeira retirada possível somente na borda seguinte. |

Em cada intervalo entre resets, a contagem de publicações deve ser igual à contagem de registros entregues, mais a ocupação atual, mais os descartes por overflow. A comparação deve incluir também a ordem e o conteúdo completo dos registros, e não apenas suas quantidades.

## 13. Pontos que precisam de alinhamento antes de aprovar o contrato

| Tema | Alinhamento necessário |
|---|---|
| Publicação do Parser | Herman: um novo registro por borda com `metadata_valid = 1`, sem repetir o mesmo pacote durante espera. |
| Representação e nomes | Parser, Hash Unit e modelo de referência: valores numéricos, ordem dos campos e nomes das portas. |
| Timestamp | Parser, verificação/TSU e features: confirmar 80 bits, unidade, formato e interpretação. |
| Comprimento | Parser e features: confirmar quais bytes compõem `packet_length`. A Flow Identification Unit apenas preserva o valor. |
| Clock e reset | Todas as equipes: clock comum, borda de subida e proposta de reset síncrono ativo baixo. |
| FIFO e perdas | Frente de metadados e integração: aprovar a localização interna, dimensionar `FIFO_DEPTH`, definir limites de chegada/bloqueio e validar a política de descartar a nova publicação. |
| Disponibilidade da Hash Unit | Samuel/integração: incluir `in_ready` na Hash Unit e sua conexão com `out_ready` desta unidade. |
| Overflow | Sistema de controle/verificação: definir o consumidor do evento e como os resultados sinalizam perdas; não conectar como evento de colisão. |
| Fim do PCAP | Verificação e Controller: definir a condição de esvaziamento da cadeia antes da finalização. |

Sem esses alinhamentos, o documento permanece uma proposta de contrato, embora as portas e o comportamento proposto estejam descritos de forma verificável.

## 14. Resumo das portas propostas

Entradas:

```text
clk
reset_n
src_ip_in[31:0]
dst_ip_in[31:0]
src_port_in[15:0]
dst_port_in[15:0]
protocol_in[7:0]
packet_length_in[15:0]
timestamp_in[79:0]
in_valid
out_ready
```

Saídas:

```text
flow_key_out[103:0]
packet_length_out[15:0]
timestamp_out[79:0]
out_valid
overflow_event
```

## 15. Fontes

- `Semana 3.docx(1).pdf`, fornecido pelo grupo: objetivo, interfaces e colunas exigidas para o contrato.
- `packet_parser_interface(1).md`, fornecido por Samuel, elaborado por Herman: portas do Parser, polaridade de reset e validade dos metadados.
- `Interfaces(1).pdf`, fornecido pelo grupo: conexões, chave de 104 bits, comprimento de 16 bits, timestamp de 80 bits e índice de 16 bits.
- [README do projeto](https://github.com/cidigital-inatel/sd392-t25s2-group2/blob/main/README.md): fluxos unidirecionais, 5-tuple e responsabilidades dos módulos.
- [Controller_interface.md](https://github.com/cidigital-inatel/sd392-t25s2-group2/blob/main/Especifica%C3%A7%C3%A3o/Extracao%20de%20Features/Controller_interface.md), consultado em 5 de outubro de 2026, blob `08844112774ba37858c23ca3d259743e5b96c081`: timestamp de 80 bits e aceitação por `in_valid && in_ready`.
- [AMD UG1483 - AXI4-Stream Support in Model Composer](https://docs.amd.com/r/en-US/ug1483-model-composer-sys-gen-user-guide/AXI4-Stream-Support-in-Model-Composer): referência para validade, disponibilidade e preservação de dados durante espera. Utilizamos essas regras de handshake em uma interface própria de registros; este documento não declara uma interface AXI4-Stream completa.
- [Consolidação da Frente 1 — Semana 3](./semana3_contratos_metadados.md): tabelas de conexão e pontos de alinhamento entre módulos.
