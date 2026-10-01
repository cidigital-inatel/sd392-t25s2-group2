**ATUALIZAÇÕES DA LÓGICA DO PACKET PARSER**

**Adaptação à interface MAC RX e integração com o TSU**

Grupo: Extração de Metadados

Documento técnico de consolidação – Semana 2

25 de setembro 2026

# 1. Objetivo

Este documento consolida as alterações realizadas na lógica do Packet
Parser após o alinhamento com o professor e a análise da interface de
recepção do MAC de referência. A principal mudança consiste em
substituir a interface genérica utilizada na primeira prova de conceito
por uma interface compatível com o fluxo RX do MAC, além de separar a
obtenção do timestamp em um módulo externo TSU.

A lógica de extração dos protocolos Ethernet II, IPv4, TCP e UDP
permanece como núcleo funcional do Parser, mas a forma de detectar
início e fim de quadro, validar a recepção e registrar o timestamp foi
atualizada.

# 2. Mudanças principais

- A entrada do Parser passa a seguir a interface RX do MAC de
  referência, baseada em TDATA, TKEEP, TVALID, TLAST e TUSER.

- O Parser deixa de utilizar TREADY. Sempre que TVALID estiver ativo, o
  módulo deve estar apto a consumir a palavra apresentada.

- Não haverá sinal explícito de SOP. O início de um novo quadro será
  inferido internamente pelo primeiro TVALID após o término do quadro
  anterior.

- O timestamp deixa de fazer parte do stream de entrada e passa a ser
  fornecido por um módulo separado, o TSU.

- O Parser somente libera os metadados ao próximo bloco após o fim do
  quadro e a confirmação de validade por TUSER.

- O IHL será utilizado para calcular dinamicamente o início do cabeçalho
  TCP ou UDP, permitindo ignorar opções IPv4 sem interpretá-las.

# 3. Interface de entrada do Packet Parser

A interface conceitual adotada para o Parser passa a refletir a
interface RX do MAC. Para fins de documentação, os nomes são
apresentados de forma simplificada, sem o prefixo rx_axis\_.

| **Sinal** | **Largura** | **Direção**  | **Função**                                              |
|-----------|-------------|--------------|---------------------------------------------------------|
| TDATA     | 64 bits     | MAC → Parser | Transporta até 8 bytes do quadro Ethernet por ciclo.    |
| TKEEP     | 8 bits      | MAC → Parser | Indica quais bytes de TDATA são válidos.                |
| TVALID    | 1 bit       | MAC → Parser | Indica que TDATA/TKEEP contêm uma transferência válida. |
| TLAST     | 1 bit       | MAC → Parser | Indica que a palavra atual contém o final do quadro.    |
| TUSER     | 1 bit       | MAC → Parser | Indica o resultado final da recepção do quadro.         |

Como a interface RX analisada não fornece TREADY, o Parser não pode
aplicar backpressure ao MAC. Assim, durante um quadro, toda palavra
apresentada com TVALID = 1 deve ser aceita e processada.

# 4. Detecção de início e fim de quadro

## 4.1. Início do quadro

A versão anterior utilizava um sinal SOP (Start of Packet). Na nova
interface, esse sinal não existe. O início de um pacote será reconhecido
quando o Parser estiver em IDLE e TVALID assumir valor 1.

> IDLE + TVALID = 1 → início de novo quadro

Nesse mesmo instante, o Parser inicializa o contexto do pacote corrente
e captura o timestamp fornecido pelo TSU.

## 4.2. Fim do quadro

O final do pacote é identificado pela última transferência válida, isto
é, quando TVALID e TLAST estão ativos no mesmo ciclo.

> fim do quadro = TVALID && TLAST

# 5. Integração com o TSU

O TSU (Timestamping Unit) será um módulo separado conectado ao Packet
Parser. Sua responsabilidade será fornecer o timestamp associado ao
instante de chegada do pacote. O Parser não deverá gerar o timestamp
internamente.

A captura deve ocorrer no início do quadro, no primeiro ciclo com TVALID
= 1 enquanto o Parser se encontra em IDLE. O valor capturado permanecerá
associado ao pacote até a conclusão do processamento.

> packet_timestamp \<= tsu_timestamp; // captura no início do quadro

A interface definitiva do TSU, incluindo largura, unidade do tempo e
eventual IP utilizado, ainda será especificada.

# 6. Validação final por TUSER

O Parser pode extrair os metadados à medida que o quadro é recebido,
porém esses metadados não devem ser considerados válidos antes da
conclusão do quadro. Ao receber TLAST, o Parser verifica TUSER.

| **TUSER** | **Interpretação** | **Ação do Parser**                         |
|-----------|-------------------|--------------------------------------------|
| 1         | Quadro válido     | Liberar os metadados para a próxima etapa. |
| 0         | Quadro inválido   | Descartar os metadados acumulados.         |

A invalidação pelo MAC pode decorrer, por exemplo, de erro de FCS,
quadro fora do tamanho permitido, MTU excedido ou outros erros
detectados durante a recepção.

# 7. Lógica de parsing dos protocolos

## 7.1. Ethernet II

O campo principal de interesse é o EtherType. Na primeira versão, apenas
quadros com EtherType = 0x0800 (IPv4) seguem para a etapa seguinte.
Demais valores são tratados como protocolos não suportados.

## 7.2. IPv4

O Parser deverá extrair e/ou validar Version, IHL, Total Length,
Protocol, Source IP e Destination IP.

- Version deve ser igual a 4.

- IHL deve ser maior ou igual a 5.

- Protocol = 6 indica TCP.

- Protocol = 17 indica UDP.

- Demais valores de Protocol são tratados como não suportados nesta PoC.

## 7.3. Uso dinâmico do IHL

O IHL não deve ser usado apenas como valor de validação. Ele também
determina o tamanho do cabeçalho IPv4, pois é expresso em palavras de 32
bits. Por isso, o tamanho do cabeçalho IPv4 em bytes é dado por IHL × 4.

> transport_offset = 14 + (IHL × 4)

O valor 14 corresponde ao cabeçalho Ethernet II sem VLAN. Com IHL = 5, o
cabeçalho IPv4 possui 20 bytes e o cabeçalho TCP/UDP começa no byte 34.
Com IHL \> 5, as opções IPv4 não serão interpretadas nem utilizadas como
features; o Parser apenas aguardará até o offset calculado.

## 7.4. TCP e UDP

Após atingir transport_offset, o Parser seleciona o protocolo de
transporte com base no campo Protocol do IPv4.

> Protocol = 6 → TCP  
> Protocol = 17 → UDP  
> outro valor → DROP_PROTO

Para TCP e UDP, os campos mínimos extraídos nesta etapa são src_port e
dst_port. As flags TCP poderão ser incorporadas futuramente caso sejam
selecionadas como features.

# 8. Pacotes suportados e não suportados

| **Condição**                  | **Classificação**                      | **Ação**                                |
|-------------------------------|----------------------------------------|-----------------------------------------|
| Ethernet II + IPv4 + TCP      | Suportado                              | Processar.                              |
| Ethernet II + IPv4 + UDP      | Suportado                              | Processar.                              |
| EtherType diferente de 0x0800 | Não suportado                          | DROP_PROTO.                             |
| Version ≠ 4                   | Não suportado / inválido para o Parser | DROP_PROTO.                             |
| IHL \< 5                      | IPv4 inválido                          | DROP_PROTO.                             |
| IHL \> 5                      | Suportado                              | Ignorar opções e localizar L4 pelo IHL. |
| Protocol diferente de 6 e 17  | Não suportado                          | DROP_PROTO.                             |
| TUSER = 0 ao final            | Quadro inválido pelo MAC               | DISCARD.                                |

# 9. FSM atualizada do Packet Parser

A FSM foi atualizada para refletir a nova interface do MAC, a captura
externa de timestamp e a validação final por TUSER.

<img src="media/image1.png"
style="width:6.5in;height:4.875in" />

*Figura 1 – FSM atualizada do Packet Parser com interface MAC RX e TSU.*

## 9.1. Estados

| **Estado**    | **Função**                                 | **Condição principal**         | **Próximo estado** |
|---------------|--------------------------------------------|--------------------------------|--------------------|
| IDLE          | Aguardar novo quadro e capturar timestamp. | TVALID = 1                     | ETHERNET           |
| ETHERNET      | Ler EtherType.                             | EtherType = 0x0800             | IPV4               |
| ETHERNET      | Detectar L3 não suportado.                 | EtherType ≠ 0x0800             | DROP_PROTO         |
| IPV4          | Validar Version/IHL e extrair campos.      | Version = 4 e IHL ≥ 5          | WAIT_L4            |
| IPV4          | Detectar IPv4 não suportado.               | Version ≠ 4 ou IHL \< 5        | DROP_PROTO         |
| WAIT_L4       | Aguardar início de TCP/UDP.                | byte_offset ≥ transport_offset | SELECT_TRANSP      |
| SELECT_TRANSP | Selecionar protocolo L4.                   | Protocol = 6                   | TCP                |
| SELECT_TRANSP | Selecionar protocolo L4.                   | Protocol = 17                  | UDP                |
| SELECT_TRANSP | Protocolo fora do escopo.                  | Outro valor                    | DROP_PROTO         |
| TCP           | Extrair src_port e dst_port.               | Campos extraídos               | WAIT_LAST          |
| UDP           | Extrair src_port e dst_port.               | Campos extraídos               | WAIT_LAST          |
| DROP_PROTO    | Ignorar quadro não suportado.              | Continuar até TLAST            | WAIT_LAST / fim    |
| WAIT_LAST     | Consumir o restante do quadro.             | TVALID && TLAST                | CHECK_FRAME        |
| CHECK_FRAME   | Verificar validade do MAC.                 | TUSER = 1                      | OUTPUT             |
| CHECK_FRAME   | Verificar validade do MAC.                 | TUSER = 0                      | DISCARD            |
| OUTPUT        | Sinalizar metadados válidos.               | Próximo ciclo                  | IDLE               |
| DISCARD       | Descartar metadados.                       | Próximo ciclo                  | IDLE               |

# 10. Impactos no ambiente de verificação

O gerador Python e o testbench deverão ser adaptados para reproduzir o
comportamento da interface RX do MAC. O arquivo de estímulos deixa de
depender de SOP, EOP, READY e timestamp integrado ao stream.

> TDATA TKEEP TVALID TLAST TUSER

O timestamp será fornecido por um mock de TSU no ambiente de simulação
até que a interface definitiva desse módulo seja especificada.

# 11. Decisões consolidadas

- Interface do Parser compatível com o MAC RX de referência.

- Sem TREADY.

- Sem SOP.

- Início de quadro inferido por TVALID quando o Parser está em IDLE.

- Fim de quadro indicado por TVALID && TLAST.

- Validade final do quadro determinada por TUSER.

- Timestamp fornecido por TSU externo e capturado no início do quadro.

- IHL utilizado para cálculo dinâmico de transport_offset.

- Opções IPv4 não são interpretadas nem usadas como features.

- Escopo inicial de parsing: Ethernet II + IPv4 + TCP/UDP.

# 12. Pendências

- Definir interface final do TSU: largura, unidade do timestamp e origem
  do clock.

- Formalizar a política para IPv4 fragmentado.

- Definir se flags TCP serão incorporadas ainda nesta etapa ou apenas em
  evolução futura.

- Atualizar o script Python e o testbench para o novo formato de
  estímulos.

# 13. Conclusão

A atualização aproxima o Packet Parser da implementação real em FPGA,
reduzindo dependências de sinais artificiais da primeira prova de
conceito. A nova organização permite que o Parser seja conectado
futuramente ao MAC de referência sem redefinir sua lógica de extração,
ao mesmo tempo em que mantém o timestamp desacoplado em um módulo TSU e
usa o IHL de forma correta para localizar dinamicamente a camada de
transporte.
