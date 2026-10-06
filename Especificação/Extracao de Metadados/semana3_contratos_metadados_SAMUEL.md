# Semana 3 — Contratos da Frente 1: Extração de Metadados

**Projeto:** Arquitetura em FPGA para Extração de Features de Fluxos TCP/IP — CI Digital Inatel, T25S2, Grupo 2.  
**Equipe:** Samuel, Bruno e Herman. Herman desenvolve o Parser; Samuel especifica Flow Identification e Hash.  
**Versão:** 0.1 — 5 de outubro de 2026.  
**Status:** proposta consolidada para revisão entre equipes. As decisões de integração indicadas como propostas ainda precisam de aprovação conjunta.

## 1. Objetivo e limite da entrega

O enunciado da Semana 3 exige identificar todas as interfaces, especificar todos os sinais, suas larguras, significados e protocolos. Também inclui as interfaces externas necessárias para conectar a Frente 1 ao restante da arquitetura. Por isso, Hash Unit → Controller faz parte desta entrega.

As tabelas abaixo utilizam as seis colunas solicitadas: **Interface, Sinal, Direção, Largura, Descrição e Protocolo**. Não se define aqui o algoritmo detalhado do CRC, a organização interna de armazenamento nem a implementação RTL.

Documentos complementares:

- [Flow Identification Unit](./flow_identification_interface.md): portas, formação da chave, publicação do Parser, retenção, disponibilidade e evento de overflow.
- [Hash Unit](./hash_unit_interface.md): portas, aceitação dos registros e entrega dos resultados ao Controller.

## 2. Convenções e origem das decisões

`Parser`, `FI`, `Hash` e `Controller` identificam os respectivos módulos. Na coluna Sinal, `origem.porta → destino.porta` explicita a ligação. As direções são relativas aos módulos indicados, não à página do diagrama.

| Item | Base existente | Tratamento nesta proposta |
|---|---|---|
| IPv4 de origem/destino: 32 bits; portas: 16 bits; protocolo: 8 bits | Parser, diagrama e README | Preservados; chave de 104 bits. |
| Comprimento: 16 bits | Parser e diagrama | Preservado, sem alteração por FI/Hash; confirmar quais bytes o Parser contabiliza. |
| Timestamp: 80 bits | Diagrama e contrato do Controller | Largura proposta para toda a cadeia; o documento do Parser fornecido ainda deixa essa largura aberta. |
| Índice: 16 bits, produzido por CRC-16 | Diagrama e README | Preservados; sem truncamento para cinco bits. |
| Parser publica sem `metadata_ready` | Documento do Parser fornecido | Proposta de um registro novo por borda com `metadata_valid = 1`. |
| Controller aceita com `in_valid && in_ready` | Documento do Controller no repositório | Preservado; explicitar o retorno de disponibilidade até a Hash Unit. |
| Retorno Hash → FI e evento de overflow | Propostas dos novos contratos | Acrescentar ao diagrama e alinhar com os consumidores. |
| Clock comum, borda de subida e reset síncrono ativo baixo | Clock/reset existem; a forma temporal não está totalmente definida nas fontes | Propostas de integração, ainda sujeitas a aprovação. |

## 3. Protocolos de transferência

Os códigos desta consolidação têm significado local a este documento. Cada contrato individual também descreve suas regras por extenso.

| Código | Regra |
|---|---|
| C | Clock comum; sinais de transferência amostrados na borda de subida. |
| R | Reset síncrono ativo baixo, proposto: a borda com `reset_n = 0` reinicializa o controle e cancela registros pendentes. Não se contabilizam transferências durante reset. |
| S | Stream sem retorno de disponibilidade: com reset inativo, toda borda com `TVALID = 1` transfere uma palavra e seus qualificadores. O fim do quadro é a borda com `TVALID && TLAST`. |
| T | Timestamp associado ao quadro: apresentar um valor estável para captura junto à primeira transferência do quadro, mantendo a associação até a publicação dos metadados. Confirmar essa regra no contrato do Parser. |
| M | Publicação sem retorno de disponibilidade: com reset inativo, cada borda com `metadata_valid = 1` representa um novo pacote, com todos os seus metadados associados. |
| H | Handshake de registros: com reset inativo, a transferência ocorre somente na borda com `valid && ready`. Enquanto `valid = 1` e `ready = 0`, o produtor mantém a validade e todos os campos estáveis. |
| O | Evento registrado: `overflow_event = 1` no ciclo após a borda em que uma publicação foi descartada por falta de capacidade. Cada ciclo ativo indica um descarte; descartes consecutivos produzem ciclos ativos consecutivos. |

O produtor de uma interface H ativa `valid` quando o registro completo está disponível, sem esperar que o consumidor ative `ready`. O consumidor só ativa `ready` quando pode aceitar o conjunto completo. Campos de dados sem validade são ignorados.

## 4. Clock e reset

| Interface | Sinal | Direção | Largura | Descrição | Protocolo |
|---|---|---|---:|---|---|
| Sistema → Parser | `Sistema.clk → Parser.clk` | Entrada do Parser | 1 bit | Clock do Parser. | C |
| Sistema → Parser | `Sistema.reset_n → Parser.reset_n` | Entrada do Parser | 1 bit | Reset ativo baixo; forma síncrona proposta. | R |
| Sistema → FI | `Sistema.clk → FI.clk` | Entrada da FI | 1 bit | Mesmo clock das interfaces de metadados. | C |
| Sistema → FI | `Sistema.reset_n → FI.reset_n` | Entrada da FI | 1 bit | Reset ativo baixo; cancela registros retidos e limpa o evento de overflow. | R |
| Sistema → Hash | `Sistema.clk → Hash.clk` | Entrada da Hash | 1 bit | Mesmo clock da FI e da interface do Controller. | C |
| Sistema → Hash | `Sistema.reset_n → Hash.reset_n` | Entrada da Hash | 1 bit | Reset ativo baixo; cancela registros pendentes e desativa as validades. | R |

O Controller precisa concordar com o domínio de clock e as condições de reset dessa interface externa. Se os domínios forem distintos, esta proposta precisa ser revisada; não contempla travessia de domínios de clock.

## 5. MAC RX / ambiente de verificação → Packet Parser

| Interface | Sinal | Direção | Largura | Descrição | Protocolo |
|---|---|---|---:|---|---|
| MAC/testbench → Parser | `TDATA[63:0]` | Entrada do Parser | 64 bits | Até oito bytes do quadro por transferência. Na convenção do gerador atual, o primeiro byte ocupa `[7:0]`. | S |
| MAC/testbench → Parser | `TKEEP[7:0]` | Entrada do Parser | 8 bits | `TKEEP[i] = 1` qualifica o byte `TDATA[8i+7:8i]`. Os demais bytes não pertencem à transferência válida. | S |
| MAC/testbench → Parser | `TVALID` | Entrada do Parser | 1 bit | A palavra e seus qualificadores estão disponíveis; cada borda ativa transfere uma palavra. | S |
| MAC/testbench → Parser | `TLAST` | Entrada do Parser | 1 bit | Última palavra do quadro; só determina fim junto com `TVALID = 1`. | S |
| MAC/testbench → Parser | `TUSER` | Entrada do Parser | 1 bit | No fim do quadro: 1 significa quadro válido e 0 significa inválido, conforme o contrato de Herman. | S |
| Verificação/TSU → Parser | `timestamp_in[79:0]` | Entrada do Parser | 80 bits | Tempo do mesmo quadro, obtido do PCAP na simulação; TSU é a origem prevista na futura FPGA. Largura proposta para alinhamento. | T |

O contrato atual não tem `TREADY`; o Parser deve consumir toda palavra com `TVALID = 1`. Uma pausa com `TVALID = 0` não transfere palavra e não encerra o quadro. Não se deve acrescentar um handshake inexistente ao descrever o contrato atual.

O gerador do repositório usa bytes nos lanes menos significativos primeiro e gera máscaras `01`, `03`, ..., `FF` para um a oito bytes. Também converte timestamps do PCAP para nanossegundos. Essas convenções documentam o estímulo atual; o formato final dos 80 bits precisa ser confirmado com Parser, verificação/TSU e features. Não foi presumido um formato dividido em segundos e nanossegundos.

## 6. Packet Parser → Flow Identification Unit

| Interface | Sinal | Direção | Largura | Descrição | Protocolo |
|---|---|---|---:|---|---|
| Parser → FI | `Parser.src_ip → FI.src_ip_in` | Saída do Parser → entrada da FI | 32 bits | IPv4 de origem do pacote publicado. | M |
| Parser → FI | `Parser.dst_ip → FI.dst_ip_in` | Saída do Parser → entrada da FI | 32 bits | IPv4 de destino do mesmo pacote. | M |
| Parser → FI | `Parser.src_port → FI.src_port_in` | Saída do Parser → entrada da FI | 16 bits | Porta TCP/UDP de origem. | M |
| Parser → FI | `Parser.dst_port → FI.dst_port_in` | Saída do Parser → entrada da FI | 16 bits | Porta TCP/UDP de destino. | M |
| Parser → FI | `Parser.protocol → FI.protocol_in` | Saída do Parser → entrada da FI | 8 bits | Campo Protocol do IPv4: 6 para TCP ou 17 para UDP nos pacotes suportados. | M |
| Parser → FI | `Parser.packet_length → FI.packet_length_in` | Saída do Parser → entrada da FI | 16 bits | Comprimento utilizado para `byte_count`, associado ao mesmo pacote. FI/Hash preservam seu valor. | M |
| Parser → FI | `Parser.timestamp → FI.timestamp_in` | Saída do Parser → entrada da FI | 80 bits | Timestamp capturado para esse pacote. Largura de integração proposta. | M |
| Parser → FI | `Parser.metadata_valid → FI.in_valid` | Saída do Parser → entrada da FI | 1 bit | Publica exatamente um registro por borda ativa, somente para pacote suportado e quadro válido. | M |

Os sete campos de dados formam um conjunto de 200 bits. Não existe retorno `ready` nessa conexão. Se `metadata_valid` permanecer alto em duas bordas, são duas publicações; portanto, o Parser não deve repetir o mesmo pacote durante uma espera downstream. Publicações de pacotes distintos em bordas consecutivas são permitidas.

## 7. Flow Identification Unit ↔ Hash Unit

| Interface | Sinal | Direção | Largura | Descrição | Protocolo |
|---|---|---|---:|---|---|
| FI → Hash | `FI.flow_key_out → Hash.flow_key_in` | Saída da FI → entrada da Hash | 104 bits | Chave unidirecional formada pelos cinco campos do pacote. | H |
| FI → Hash | `FI.packet_length_out → Hash.packet_length_in` | Saída da FI → entrada da Hash | 16 bits | Comprimento do mesmo pacote da chave apresentada. | H |
| FI → Hash | `FI.timestamp_out → Hash.timestamp_in` | Saída da FI → entrada da Hash | 80 bits | Timestamp do mesmo pacote da chave apresentada. | H |
| FI → Hash | `FI.out_valid → Hash.in_valid` | Saída da FI → entrada da Hash | 1 bit | O conjunto de 200 bits está disponível para aceitação. | H |
| Hash → FI | `Hash.in_ready → FI.out_ready` | Saída da Hash → entrada da FI | 1 bit | A Hash Unit tem capacidade real para aceitar e preservar um registro completo nesta borda. | H |

O evento de transferência é `FI.out_valid && FI.out_ready`, equivalente a `Hash.in_valid && Hash.in_ready`. Durante espera, a FI preserva a saída mais antiga. O retorno de disponibilidade é uma conexão proposta que precisa aparecer no diagrama.

### Composição da chave

`flow_key = {src_ip, dst_ip, src_port, dst_port, protocol}`.

| Campo | Bits da chave | Largura |
|---|---|---:|
| Origem IPv4 | `[103:72]` | 32 bits |
| Destino IPv4 | `[71:40]` | 32 bits |
| Porta de origem | `[39:24]` | 16 bits |
| Porta de destino | `[23:8]` | 16 bits |
| Protocolo | `[7:0]` | 8 bits |

A representação numérica proposta utiliza os valores convencionais: `192.168.1.10` corresponde a `32'hC0A8010A` e a porta 50000 a `16'hC350`. Essa representação dos campos já extraídos deve ser confirmada com o Parser; não se confunde com a posição dos bytes no stream de entrada. Não há ordenação de origem/destino para agrupar os dois sentidos de uma conexão.

## 8. Hash Unit ↔ Controller

| Interface | Sinal | Direção | Largura | Descrição | Protocolo |
|---|---|---|---:|---|---|
| Hash → Controller | `Hash.hash_index_out → Controller.hash_index` | Saída da Hash → entrada do Controller | 16 bits | Índice CRC-16 derivado da chave; todos os 16 bits são preservados. | H |
| Hash → Controller | `Hash.flow_key_out → Controller.flow_key` | Saída da Hash → entrada do Controller | 104 bits | Chave completa do registro cujo índice é apresentado. | H |
| Hash → Controller | `Hash.packet_length_out → Controller.packet_length` | Saída da Hash → entrada do Controller | 16 bits | Comprimento preservado do mesmo pacote. | H |
| Hash → Controller | `Hash.timestamp_out → Controller.timestamp` | Saída da Hash → entrada do Controller | 80 bits | Timestamp preservado do mesmo pacote. | H |
| Hash → Controller | `Hash.out_valid → Controller.in_valid` | Saída da Hash → entrada do Controller | 1 bit | Índice e três campos associados estão disponíveis como um conjunto. | H |
| Controller → Hash | `Controller.in_ready → Hash.out_ready` | Saída do Controller → entrada da Hash | 1 bit | O Controller pode aceitar o registro completo nesta borda. | H |

O conjunto de saída tem 216 bits de dados: 16 de índice, 104 de chave, 16 de comprimento e 80 de timestamp. O evento de entrega é `Hash.out_valid && Hash.out_ready`, equivalente a `Controller.in_valid && Controller.in_ready`.

O índice é calculado exclusivamente a partir da chave. A chave, o comprimento e o timestamp seguem associados ao mesmo registro. A chave completa permite ao Controller distinguir chaves que produzem o mesmo índice; a decisão HIT/MISS/COLLISION permanece na Frente 2.

O contrato do Controller já exige o retorno de disponibilidade. O diagrama fornecido ainda não mostra essa ligação; deixar apenas o sinal de validade permitiria perder registros durante a indisponibilidade do Controller.

## 9. Evento externo de falta de capacidade

| Interface | Sinal | Direção | Largura | Descrição | Protocolo |
|---|---|---|---:|---|---|
| FI → controle/verificação | `FI.overflow_event` | Saída da FI → entrada do consumidor a designar | 1 bit | Descarte integral de uma nova publicação por falta de capacidade, sem alterar registros pendentes. Consumidor precisa ser definido pela integração. | O |

Como o Parser não recebe `ready`, a proposta da FI inclui retenção de registros e sinalização de perda. Se a capacidade estiver esgotada, uma retirada na mesma borda pode abrir lugar para a nova publicação; sem retirada, descarta-se somente a nova publicação. Uma fila finita não garante ausência de perdas para bloqueios ilimitados. A profundidade não foi arbitrada nesta entrega.

A localização da retenção, a política de perdas e o destino do evento são propostas de contrato. Se o grupo preferir outra solução, deve alterar de forma consistente as portas e o protocolo afetados antes de aprovar a especificação.

## 10. Alinhamentos ainda necessários na Semana 3

Os documentos especificam uma proposta verificável. Os itens abaixo são pendências reais de alinhamento do contrato, não autorização para iniciar RTL ou etapas seguintes.

| Tema | O que está documentado | O que precisa ser acordado |
|---|---|---|
| Timestamp | 80 bits no diagrama e no Controller; estímulo atual em nanossegundos | Fixar 80 bits também no Parser; registrar unidade, formato, interpretação e instante de captura para toda a cadeia. |
| Comprimento | 16 bits preservados de ponta a ponta | Definir quais bytes compõem `packet_length` e sua relação com `byte_count`. |
| Publicação do Parser | Um novo registro por borda com validade ativa | Confirmar com Herman que o mesmo pacote não é publicado novamente durante espera. |
| Clock/reset | Clock comum, borda de subida e reset síncrono ativo baixo propostos | Confirmar a mesma convenção com Parser, Hash e Controller. |
| Campos e nomes | Concatenação de 104 bits e mapeamentos entre portas | Confirmar representação numérica e nomes finais; atualizar os contratos correspondentes. |
| Disponibilidade | `Hash.in_ready → FI.out_ready` e `Controller.in_ready → Hash.out_ready` | Acrescentar as duas ligações ao diagrama e conferir sua implementação futura. |
| Retenção/perdas | FI retém; em overflow descarta a nova publicação e sinaliza o evento | Aprovar política e localização; definir consumidor do evento. Dimensionar a capacidade quando houver limites de chegada e atendimento. |
| Fim do PCAP | `pcap_done` pertence ao ambiente/Controller, não à FI/Hash | Definir a condição global de esvaziamento antes da finalização. Uma validade desativada isoladamente não prova que todos os registros foram processados. |

A definição de variante, parâmetros e ordem de processamento do CRC, os limites de desempenho do circuito e o RTL ficam para a etapa correspondente. A ausência desses detalhes não altera o significado dos sinais `valid/ready` documentados aqui. Já as pendências de significado, conexões e protocolo acima precisam ser resolvidas para que o contrato seja considerado aprovado.

## 11. Cobertura do enunciado

| Exigência da Semana 3 | Local da documentação |
|---|---|
| Identificar interfaces | Seções 4–9, incluindo conexões externas. |
| Especificar todos os sinais | Tabelas de seis colunas e contratos individuais. |
| Definir larguras | Tabelas: chave 104, comprimento 16, timestamp 80 proposto, índice 16 e controles de 1 bit. |
| Documentar significados | Descrições por sinal, formação da chave e regras de associação dos registros. |
| Definir protocolo | Seção 3 e regras temporais dos contratos individuais. |

Antes da aprovação, conferir as correspondências Parser → FI, FI ↔ Hash e Hash ↔ Controller, incluindo os dois retornos de disponibilidade. Depois de acordar os itens da seção 10, atualizar Parser, diagrama e contrato do Controller onde forem afetados, mantendo todos os documentos consistentes.

## 12. Fontes consultadas

- `Semana 3.docx(1).pdf`: objetivo, escopo, interfaces externas e formato da tabela.
- `packet_parser_interface(1).md`, elaborado por Herman: portas e regras atuais do Parser.
- `Interfaces(1).pdf`: dados, conexões e larguras do caminho de metadados.
- [README do projeto](https://github.com/cidigital-inatel/sd392-t25s2-group2/blob/main/README.md): fluxos unidirecionais, chave de 104 bits, CRC-16 e função do Controller.
- [Controller_interface.md](https://github.com/cidigital-inatel/sd392-t25s2-group2/blob/main/Especifica%C3%A7%C3%A3o/Extracao%20de%20Features/Controller_interface.md), consultado em 5 de outubro de 2026, blob `08844112774ba37858c23ca3d259743e5b96c081`: nomes das portas, timestamp de 80 bits e `in_valid && in_ready`.
- [Gerador PCAP → stream](https://github.com/cidigital-inatel/sd392-t25s2-group2/blob/main/Especifica%C3%A7%C3%A3o/Verificacao/codigo_pcap_para_txt_comeco_mac.py), consultado em 5 de outubro de 2026, blob `8c14767dbc1b3f50c7c8aff1fb6773951aa6aa8a`: `keep_mask`, `data_to_axi_hex` e `timestamp_to_ns`.
- [AMD UG1483 — AXI4-Stream Support in Model Composer](https://docs.amd.com/r/en-US/ug1483-model-composer-sys-gen-user-guide/AXI4-Stream-Support-in-Model-Composer): referência para as regras de handshake e estabilidade de dados. As interfaces FI/Hash/Controller são contratos próprios de registros; não se declara uma interface AXI4-Stream completa.
