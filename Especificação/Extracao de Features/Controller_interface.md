# Contrato de Interface — Controller

Este documento registra exclusivamente o contrato de interface do módulo **Controller**, considerando a arquitetura proposta para a extração de features de fluxos TCP/IP em hardware, incluindo a comunicação com a Flow Table e o Flow Finalizer.

---

## 1. Entradas

| **Sinal**         | **Largura** | **Direção** | **Origem**             | **Descrição**                                                                  |
| ----------------- | ----------: | ----------- | ---------------------- | ------------------------------------------------------------------------------ |
| `clk`             |       1 bit | Entrada     | Sistema                | Clock do Controller.                                                           |
| `reset_n`         |       1 bit | Entrada     | Sistema                | Reset ativo em nível baixo.                                                    |
| `flow_key`        |    104 bits | Entrada     | Hash Unit              | Chave que identifica o fluxo, formada por IPs, portas e protocolo.             |
| `hash_index`      |     16 bits | Entrada     | Hash Unit              | Índice calculado pela Hash Unit para localizar a entrada na Flow Table.        |
| `packet_length`   |     16 bits | Entrada     | Hash Unit              | Comprimento do pacote utilizado na atualização de `byte_count`.                |
| `timestamp`       |     80 bits | Entrada     | Hash Unit              | Timestamp associado ao pacote recebido.                                        |
| `in_valid`        |       1 bit | Entrada     | Hash Unit              | Indica que os metadados apresentados na entrada são válidos.                   |
| `pcap_done`       |       1 bit | Entrada     | Sistema de verificação | Indica que todos os pacotes do arquivo PCAP foram enviados para processamento. |
| `ctrl_restart`    |       1 bit | Entrada     | Sistema de controle    | Solicita o reinício do Controller após a conclusão do processamento.           |
| `rd_data`         |     16 bits | Entrada     | Flow Table / memória   | Palavra retornada pela operação de leitura da Flow Table.                      |
| `rd_valid`        |       1 bit | Entrada     | Flow Table / memória   | Indica que o dado solicitado está disponível na saída da memória.              |
| `wr_done`         |       1 bit | Entrada     | Flow Table / memória   | Indica que a operação de escrita solicitada foi concluída.                     |
| `finalizer_ready` |       1 bit | Entrada     | Flow Finalizer         | Indica que o Finalizer está pronto para receber um registro.                   |
| `finalizer_done`  |       1 bit | Entrada     | Flow Finalizer         | Indica que o processamento do registro enviado ao Finalizer foi concluído.     |

---

## 2. Saídas

| **Sinal**         | **Largura** | **Direção** | **Descrição**                                                                                         |
| ----------------- | ----------: | ----------- | ----------------------------------------------------------------------------------------------------- |
| `in_ready`        |       1 bit | Saída       | Indica que o Controller está pronto para aceitar novos metadados.                                     |
| `rd_en`           |       1 bit | Saída       | Solicita uma operação de leitura na Flow Table.                                                       |
| `rd_addr`         |     21 bits | Saída       | Endereço da palavra a ser lida na Flow Table.                                                         |
| `wr_en`           |       1 bit | Saída       | Solicita uma operação de escrita na Flow Table.                                                       |
| `wr_addr`         |     21 bits | Saída       | Endereço da palavra a ser escrita na Flow Table.                                                      |
| `wr_data`         |     16 bits | Saída       | Palavra de 16 bits a ser escrita na Flow Table.                                                       |
| `finalizer_valid` |       1 bit | Saída       | Indica que um registro está disponível para ser recebido pelo Finalizer.                              |
| `flow_entry`      |    384 bits | Saída       | Registro enviado ao Flow Finalizer, conforme a interface apresentada na especificação inicial.        |
| `fin_en`          |       1 bit | Saída       | Sinal de habilitação do Flow Finalizer, conforme a interface apresentada no PDF.                      |
| `all_flows_done`  |       1 bit | Saída       | Indica que a varredura da Flow Table e o processamento de todas as entradas válidas foram concluídos. |
| `collision_event` |       1 bit | Saída       | Sinaliza a ocorrência de colisão entre chaves de fluxos.                                              |
| `collision_count` |     32 bits | Saída       | Contador de colisões detectadas durante o processamento.                                              |

---

## 3. Interface com a Flow Table

A Flow Table armazena as informações dos fluxos identificados durante o processamento dos pacotes.

| **Sinal**  | **Largura** | **Direção em relação ao Controller** | **Descrição**                                 |
| ---------- | ----------: | ------------------------------------ | --------------------------------------------- |
| `rd_en`    |       1 bit | Saída                                | Solicita a leitura de uma palavra da memória. |
| `rd_addr`  |     21 bits | Saída                                | Endereço da palavra a ser lida.               |
| `rd_data`  |     16 bits | Entrada                              | Dado retornado pela memória.                  |
| `rd_valid` |       1 bit | Entrada                              | Indica que o dado lido está disponível.       |
| `wr_en`    |       1 bit | Saída                                | Solicita a escrita de uma palavra na memória. |
| `wr_addr`  |     21 bits | Saída                                | Endereço da palavra a ser escrita.            |
| `wr_data`  |     16 bits | Saída                                | Dado a ser armazenado.                        |
| `wr_done`  |       1 bit | Entrada                              | Indica a conclusão da operação de escrita.    |

### Organização da memória

A Flow Table possui 65.536 entradas, cada uma com 512 bits, organizados em 32 palavras de 16 bits.

| **Palavras** | **Campo**               |         **Largura** |
| ------------ | ----------------------- | ------------------: |
| W0           | `valid` e preenchimento |             16 bits |
| W1–W7        | `flow_key`              | 112 bits reservados |
| W8–W9        | `packet_count`          |             32 bits |
| W10–W13      | `byte_count`            |             64 bits |
| W14–W18      | `first_timestamp`       |             80 bits |
| W19–W23      | `last_timestamp`        |             80 bits |
| W24–W31      | Reservado               |            128 bits |

O endereço base de cada entrada é calculado a partir do índice de hash:

```text
base_addr = hash_index << 5
```

Os cinco bits menos significativos do endereço identificam a palavra dentro da entrada.

---

## 4. Interface com o Flow Finalizer

A interface do Flow Finalizer mantém os sinais e as larguras apresentados na especificação inicial do PDF.

| **Sinal**        | **Largura** | **Direção em relação ao Controller** | **Descrição**                                                              |
| ---------------- | ----------: | ------------------------------------ | -------------------------------------------------------------------------- |
| `fin_en`         |       1 bit | Saída                                | Sinal de habilitação do Flow Finalizer.                                    |
| `flow_entry`     |    384 bits | Saída                                | Registro de entrada encaminhado ao Flow Finalizer.                         |
| `feature_vector` |    280 bits | Entrada                              | Vetor de features apresentado pela interface do Finalizer, conforme o PDF. |
| `wr_done`        |       1 bit | Entrada                              | Sinal de conclusão de escrita indicado na interface inicial.               |
| `done`           |       1 bit | Entrada                              | Sinal de conclusão apresentado pelo Flow Finalizer.                        |

**Observação:** a composição de `flow_entry` e `feature_vector`, assim como a função exata de `wr_done` e `done`, ainda precisa ser confirmada. Esses sinais foram mantidos conforme o PDF, sem atribuir funções adicionais que não estão descritas nele.

---

## 5. Regras de funcionamento da interface

| **Condição**                     | **Contrato**                                                                                                                                              |
| -------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Recepção de metadados            | O Controller aceita os metadados quando `in_valid && in_ready = 1`.                                                                                       |
| Endereçamento                    | O Controller utiliza `hash_index` para calcular o endereço base da entrada na Flow Table.                                                                 |
| Leitura da entrada               | O Controller ativa `rd_en` e apresenta `rd_addr` para solicitar a leitura da entrada correspondente.                                                      |
| Disponibilidade da leitura       | O Controller aguarda `rd_valid = 1` antes de utilizar o dado retornado pela memória.                                                                      |
| Fluxo inexistente                | Quando o bit `valid` da entrada lida está desativado, o Controller inicializa uma nova entrada.                                                           |
| Fluxo existente                  | Quando a chave armazenada coincide com `flow_key`, o Controller atualiza as estatísticas do fluxo.                                                        |
| Colisão                          | Quando a entrada está ocupada por uma chave diferente, o Controller sinaliza a colisão e descarta o pacote.                                               |
| Atualização de pacotes           | Para um fluxo existente, `packet_count` é incrementado em uma unidade.                                                                                    |
| Atualização de bytes             | Para cada pacote processado, `byte_count` é incrementado pelo valor de `packet_length`.                                                                   |
| Atualização temporal             | Na criação de um fluxo, `first_timestamp` e `last_timestamp` recebem o timestamp do pacote. Nos pacotes seguintes, somente `last_timestamp` é atualizado. |
| Escrita na memória               | O Controller ativa `wr_en` e apresenta o endereço e os dados correspondentes à operação de escrita.                                                       |
| Conclusão da escrita             | O Controller aguarda `wr_done` para considerar concluída a operação de escrita.                                                                           |
| Finalização do PCAP              | Quando `pcap_done = 1` e o Controller está disponível para iniciar a finalização, começa a varredura da Flow Table.                                       |
| Envio ao Finalizer               | As entradas válidas encontradas durante a varredura são encaminhadas ao Flow Finalizer.                                                                   |
| Conclusão global                 | `all_flows_done` é ativado após a varredura completa e a conclusão do processamento da última entrada válida.                                             |
| Reinicialização do processamento | `ctrl_restart` permite retornar ao estado inicial após a conclusão global.                                                                                |

---

## 6. Resumo da interface

### Entradas

```text
clk
reset_n

flow_key[103:0]
hash_index[15:0]
packet_length[15:0]
timestamp[79:0]
in_valid
pcap_done
ctrl_restart

rd_data[15:0]
rd_valid
wr_done

finalizer_ready
finalizer_done
```

### Saídas

```text
in_ready

rd_en
rd_addr[20:0]

wr_en
wr_addr[20:0]
wr_data[15:0]

fin_en
flow_entry[383:0]
finalizer_valid

all_flows_done
collision_event
collision_count[31:0]
```

**Observação final:** `feature_vector[279:0]`, `wr_done` e `done` foram preservados na descrição da interface original do Finalizer. Como a relação entre esses sinais e o Controller ainda não está completamente definida, será necessário confirmar suas direções e responsabilidades antes da implementação RTL definitiva.
