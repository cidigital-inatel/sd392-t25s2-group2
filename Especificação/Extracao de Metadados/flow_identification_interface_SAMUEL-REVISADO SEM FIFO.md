# Contrato de Interface - Flow Identification Unit

**Projeto:** Arquitetura em FPGA para Extração de Features de Fluxos TCP/IP - CI Digital Inatel, T25S2, Grupo 2.  
**Frente:** Extração de Metadados - Samuel, Bruno e Herman.  
**Versão:** 0.3 - 6 de outubro de 2026.  
**Status:** proposta para revisão e alinhamento entre equipes. Não constitui contrato aprovado nem evidência de implementação RTL.

Este documento especifica as portas e o comportamento temporal propostos para a Flow Identification Unit. Segue o formato de contrato solicitado na Semana 3 e utiliza como referência a interface do Packet Parser elaborada por Herman e o diagrama de interfaces fornecido pelo grupo.

**Limite desta entrega:** sinais, larguras, significados, conexões e protocolo de transferência. O algoritmo CRC e a implementação RTL não são definidos nesta Semana 3.

**Revisão desta versão:** a FIFO deixa de ser exigida na proposta da PoC, conforme a orientação do professor Elivander relatada por Samuel em 6 de outubro de 2026. A indicação de que ela é provavelmente dispensável é registrada como premissa de operação, sem afirmar uma comprovação numérica de desempenho. Mantém-se a preservação de um único registro de saída até sua aceitação pela Hash Unit.

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
| Operação sem FIFO na PoC | Orientação do professor Elivander, relatada por Samuel | Tempo de recepção maior que o de processamento e folga entre pacotes; não exigir fila de vários registros nesta versão. |
| Preservação do registro de saída | Proposta de protocolo | Até um registro pendente nesta unidade; mantê-lo estável até a aceitação pela Hash Unit. |
| `out_ready` da Flow Identification Unit | Proposta de protocolo | Retorno de disponibilidade que precisa ser incorporado ao diagrama e ao contrato da Hash Unit. |

## 2. Responsabilidade funcional

A Flow Identification Unit recebe do Packet Parser a 5-tuple, o comprimento e o timestamp de um pacote. Forma uma chave de 104 bits, preserva as demais informações e disponibiliza o registro completo para a Hash Unit, na ordem de chegada.

Nesta proposta, não há fila para acumular vários registros. A unidade recebe publicações do Parser sem retorno de disponibilidade e entrega um registro de saída por handshake `valid/ready`. A preservação desse único registro pode ser realizada com registradores de saída, sem exigir uma FIFO de pacotes.

O cálculo do CRC, a consulta da Flow Table, a detecção de colisões e a atualização das features pertencem aos módulos seguintes. A validação de Ethernet/IPv4/TCP/UDP e a verificação final do quadro permanecem sob responsabilidade do Parser.

O timestamp e o comprimento são encaminhados sem alteração e não fazem parte da chave de fluxo.

## 3. Interfaces identificadas

1. Sistema -> Flow Identification Unit: clock e reset.
2. Packet Parser -> Flow Identification Unit: campos e validade de uma publicação.
3. Flow Identification Unit -> Hash Unit: registro completo e validade da saída.
4. Hash Unit -> Flow Identification Unit: disponibilidade para aceitar a saída.

Todas as direções das tabelas seguintes são relativas à Flow Identification Unit. Os sufixos `_in` e `_out` indicam a direção da porta de dados. Os nomes são propostos para este módulo, sem renomear as portas existentes do Parser.

## 4. Protocolos utilizados nas tabelas

| Código | Protocolo |
|---|---|
| P0 | Clock comum ao Parser, Flow Identification Unit, Hash Unit e Controller; eventos de transferência amostrados na borda de subida. |
| P1 | Reset síncrono ativo baixo: uma borda com `reset_n = 0` cancela o registro pendente e desativa a validade, com prioridade sobre entradas e saídas. |
| P2 | Publicação sem retorno de disponibilidade: em cada borda com `reset_n = 1` e `in_valid = 1`, os campos de entrada representam exatamente um novo registro. |
| P3 | Handshake de saída: o registro é aceito pela Hash Unit em uma borda com `reset_n = 1`, `out_valid = 1` e `out_ready = 1`. |

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

Não há `in_ready` de saída para o Parser nesta proposta. Portanto, a unidade não pode solicitar ao Parser que suspenda suas publicações. `out_ready` indica exclusivamente a aceitação do registro de saída pela Hash Unit. O sinal `overflow_event` da versão anterior é retirado da interface desta versão.

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
- Repetir uma chave em dois pacotes não autoriza eliminar um dos registros. Cada publicação representa um pacote que precisa contribuir para as estatísticas.

## 8. Operação sem FIFO na PoC

O professor Elivander explicou, segundo o relato de Samuel, que o tempo de recepção de pacotes é muito maior que o de processamento e que há folga suficiente entre pacotes. Esta versão usa essa orientação para dispensar uma FIFO de múltiplos registros.

O registro de saída reúne 104 bits de chave, 16 bits de comprimento e 80 bits de timestamp: 200 bits de dados. A unidade pode preservar **um único registro pendente** enquanto aguarda a Hash Unit. Registradores de saída cumprem a função de manter esse conjunto estável; não oferecem uma fila para acumular vários pacotes.

O sinal de validade é controle e não integra os 200 bits. Não há parâmetro de profundidade de FIFO nem política normal de descarte por fila cheia nesta versão.

### Premissa temporal do contrato

Como o Parser não recebe disponibilidade de volta, o tráfego da PoC deve permitir a aceitação do registro anterior antes de uma publicação que precisaria ocupar sua saída ainda bloqueada. Em cada borda, com reset inativo, uma nova publicação só é admissível quando:

- não existe registro pendente na saída; ou
- o registro pendente é aceito pela Hash Unit nessa mesma borda.

Em termos dos sinais: se `in_valid = 1`, então `out_valid = 0` ou `out_ready = 1` deve ser verdadeiro antes da borda.

Uma condição conservadora para sustentar essa premissa é o tempo máximo para liberar o caminho de processamento ser menor que o intervalo mínimo entre publicações de metadados, incluindo eventuais esperas da Hash Unit pelo Controller. O intervalo relevante é entre registros publicados pelo Parser, e não apenas a média de chegada dos pacotes.

Essa condição registra o significado da folga informada pelo orientador; não atribui um número de ciclos nem afirma que tenha sido medida nesta entrega. Sua conferência numérica pertence à futura verificação de desempenho da PoC.

## 9. Regras de publicação e aceitação

### 9.1. Publicação do Parser

Com reset inativo, cada borda com `in_valid = 1` publica um novo registro. Os sete campos de dados devem estar estáveis antes dessa borda, com os requisitos de temporização do sistema.

Uma publicação ocupa exatamente uma borda por pacote. Não se utiliza detector de borda de subida de validade. Publicações em bordas consecutivas são admissíveis somente quando atendem a condição de disponibilidade da seção 8; esta possibilidade do protocolo não constitui promessa de processamento de um pacote por ciclo.

Com `in_valid = 0`, os dados de entrada são ignorados. A Flow Identification Unit não interpreta `TVALID`, `TLAST` ou `TUSER`; recebe a validade já consolidada pelo Parser.

### 9.2. Apresentação do registro

Uma publicação admissível capturada na borda E forma a chave e passa a ser apresentada, com comprimento e timestamp associados, durante o ciclo seguinte. Sua primeira aceitação pela Hash Unit é possível na borda E+1.

Esta versão propõe uma saída registrada, sem passagem direta da publicação nova para a Hash Unit na mesma borda de captura. Essa regra temporal não exige uma FIFO; descreve o alinhamento dos dados com a validade na interface.

`out_valid` é ativado quando o registro completo está disponível, sem aguardar `out_ready`. Enquanto `out_valid = 1` e `out_ready = 0`, os três campos e a validade permanecem estáveis.

### 9.3. Aceitação e substituição da saída

A borda com `out_valid && out_ready` transfere exatamente um registro para a Hash Unit. Se não houver nova publicação nessa borda, a validade é desativada após a transferência.

Se houver uma nova publicação admissível na mesma borda, a Hash Unit captura o registro antigo; a saída passa a apresentar o novo registro no ciclo seguinte. Não se exige um ciclo com validade zero entre essas duas transferências.

Nenhuma nova publicação pode sobrescrever um registro que ainda aguarda aceitação.

### 9.4. Publicação durante bloqueio

`in_valid = 1`, `out_valid = 1` e `out_ready = 0` na mesma borda violam a premissa desta versão sem FIFO. Não há capacidade para conservar ambos os registros, e o Parser não possui sinal para repetir a publicação.

Nessa condição, o registro de saída já pendente deve permanecer estável. A nova publicação não pode ser retida por este contrato; o cenário deve ser identificado pelo ambiente de verificação como violação da premissa, não tratado como operação normal com descarte autorizado. Não é introduzida uma porta de overflow ou um mecanismo de recuperação.

## 10. Exemplo temporal

A e B representam registros completos. O exemplo mostra uma espera curta que termina antes da próxima publicação, respeitando a operação sem fila de vários registros.

As entradas, a saída e `out_ready` são valores antes da borda. A última coluna mostra a saída depois da borda. O reset está inativo, exceto em E0.

| Borda | Publicação do Parser | Saída antes da borda | `out_ready` | Ação na borda | Saída após a borda |
|---|---|---|---:|---|---|
| E0 | Ignorada por reset | Sem transferência | 0 | Reset | Nenhuma válida |
| E1 | A, `in_valid = 1` | Nenhuma válida | 0 | Capturar A | A válido |
| E2 | Nenhuma, `in_valid = 0` | A válido | 0 | Aguardar, preservando A | A válido e estável |
| E3 | Nenhuma, `in_valid = 0` | A válido | 1 | Entregar A | Nenhuma válida |
| E4 | Nenhuma, `in_valid = 0` | Nenhuma válida | 1 | Aguardar próximo pacote | Nenhuma válida |
| E5 | B, `in_valid = 1` | Nenhuma válida | 1 | Capturar B | B válido |
| E6 | Nenhuma, `in_valid = 0` | B válido | 1 | Entregar B | Nenhuma válida |

A é entregue uma vez em E3 e B uma vez em E6. Não há entrega de B em E5: antes dessa borda, a nova saída ainda não estava válida. Nenhuma publicação foi acumulada atrás de outra nesta unidade.

## 11. Reset e delimitação do processamento

Nesta versão, propomos reset síncrono ativo baixo. Uma borda com `reset_n = 0` cancela o registro pendente e desativa a validade, com prioridade sobre entrada e saída. Registros anteriores ao reset não podem reaparecer depois da retomada.

Não há exigência de valor dos campos de saída quando `out_valid = 0`. Eles não devem ser utilizados pelo receptor.

A forma síncrona de reset e o uso de clock comum devem ser confirmados com o Parser e a Hash Unit. Sinais provenientes de outro domínio de clock não podem ser ligados diretamente sob este contrato.

Esta unidade não recebe nem gera `pcap_done`. Mesmo sem FIFO, pode existir um registro aguardando na saída ou em processamento na Hash Unit/Controller. A verificação deve esperar a conclusão dos registros pendentes antes da finalização global. A saída da FI estar inválida, isoladamente, não demonstra que o último registro já foi processado pelo Controller.

## 12. Critérios de verificação

Os itens abaixo conferem o comportamento externo da proposta. Não representam implementação ou simulação RTL já executada.

| Cenário | Resultado esperado |
|---|---|
| Campos do exemplo da seção 7 | Chave exatamente `104'hC0A8010AC0A80114C35001BB06`. |
| Mesma 5-tuple, comprimentos/timestamps diferentes | Mesma chave; preservar separadamente os dados de cada publicação admissível. |
| Inversão de origem/destino do exemplo | Chave diferente, com as posições trocadas. |
| `in_valid = 0` com dados variando | Nenhuma captura. |
| Publicação quando a saída não tem registro pendente | Captura do conjunto; apresentação válida no ciclo seguinte. |
| `out_valid = 1` e `out_ready = 0` | Dados e validade estáveis; nenhuma entrega. |
| `out_valid = 1` e `out_ready = 1`, sem publicação | Uma entrega; validade desativada depois da borda. |
| Entrega e publicação na mesma borda | Entregar o registro antigo e apresentar o novo depois da borda. |
| Publicação com saída pendente e Hash indisponível | Violação da premissa temporal; saída anterior preservada, sem capacidade para reter a nova publicação. |
| Reset com saída pendente | Cancelamento; nenhum registro anterior reaparece. |
| Intervalo entre publicações | Compatível com a liberação da saída, incluindo bloqueios provenientes de Hash/Controller. |

Em um intervalo sem reset e iniciado sem registro pendente, **para publicações que respeitam a premissa**, a quantidade de publicações é igual à de registros entregues mais o registro eventualmente pendente (zero ou um). Conferir também conteúdo e ordem, não apenas quantidade.

## 13. Pontos que precisam de alinhamento antes de aprovar o contrato

| Tema | Alinhamento necessário |
|---|---|
| Publicação do Parser | Herman: um novo registro por borda com `metadata_valid = 1`, sem repetir o mesmo pacote durante espera. |
| Representação e nomes | Parser, Hash Unit e modelo de referência: valores numéricos, ordem dos campos e nomes finais. |
| Timestamp | Parser, verificação/TSU e features: confirmar 80 bits, unidade, formato e interpretação. |
| Comprimento | Parser e features: confirmar quais bytes compõem `packet_length`; esta unidade preserva o valor. |
| Clock e reset | Todas as equipes: clock comum, borda de subida e reset síncrono ativo baixo proposto. |
| Operação sem FIFO | Registrar a orientação do professor Elivander e a condição de publicação admissível nos contratos de integração; conferir futuramente a premissa no tráfego da PoC. Não exigir dimensionamento de uma fila nesta versão. |
| Disponibilidade da Hash Unit | Incluir `Hash.in_ready → FI.out_ready`; a retirada da FIFO não elimina o handshake. |
| Fim do PCAP | Verificação e Controller: definir a condição de término dos registros pendentes antes da finalização. |

A orientação recebida esclarece o ponto da FIFO. Os demais alinhamentos permanecem necessários; o documento continua sendo uma proposta de contrato.

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
```

## 15. Fontes

- Orientação do professor Elivander, relatada por Samuel em 6 de outubro de 2026: FIFO provavelmente dispensável pela folga entre recepção e processamento. Informação qualitativa fornecida pelo grupo, não medição executada nesta entrega.
- `Semana 3.docx(1).pdf`, fornecido pelo grupo: objetivo, interfaces e colunas exigidas para o contrato.
- `packet_parser_interface(1).md`, fornecido por Samuel, elaborado por Herman: portas do Parser, polaridade de reset e validade dos metadados.
- `Interfaces(1).pdf`, fornecido pelo grupo: conexões, chave de 104 bits, comprimento de 16 bits, timestamp de 80 bits e índice de 16 bits.
- [README do projeto](https://github.com/cidigital-inatel/sd392-t25s2-group2/blob/main/README.md): fluxos unidirecionais, 5-tuple e responsabilidades dos módulos.
- [Controller_interface.md](https://github.com/cidigital-inatel/sd392-t25s2-group2/blob/main/Especifica%C3%A7%C3%A3o/Extracao%20de%20Features/Controller_interface.md), consultado em 5 de outubro de 2026, blob `08844112774ba37858c23ca3d259743e5b96c081`: timestamp de 80 bits e aceitação por `in_valid && in_ready`.
- [AMD UG1483 - AXI4-Stream Support in Model Composer](https://docs.amd.com/r/en-US/ug1483-model-composer-sys-gen-user-guide/AXI4-Stream-Support-in-Model-Composer): referência para validade, disponibilidade e preservação de dados durante espera. Utilizamos essas regras de handshake em uma interface própria de registros; este documento não declara uma interface AXI4-Stream completa.
- [Consolidação da Frente 1 — Semana 3](./semana3_contratos_metadados.md): tabelas de conexão e pontos de alinhamento entre módulos.
