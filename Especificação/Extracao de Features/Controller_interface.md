# Contrato de Interface — Controller

## 1. Objetivo

O módulo **Controller** coordena a leitura e a escrita na Flow Table e o envio das entradas ao Flow Finalizer para extração de features.

Suas responsabilidades são:
- Receber os metadados dos fluxos.
- Consultar e atualizar entradas da Flow Table.
- Controlar o envio das entradas ao Flow Finalizer.
- Aguardar a conclusão do processamento pelo Flow Finalizer.

## 2. Entradas

| Sinal | Largura | Origem | Descrição |
|---|---:|---|---|
| `clk` | 1 bit | Sistema | Clock do Controller. |
| `reset` | 1 bit | Sistema | Reinicialização do Controller. |
| `hash_index` | 16 bits | Hash Unit | Índice calculado para localizar a entrada na Flow Table. |
| `flow_key` | 104 bits | Hash Unit | Chave de identificação do fluxo. |
| `packet_length` | 16 bits | Hash Unit | Comprimento do pacote recebido. |
| `timestamp` | 80 bits | Sistema de metadados | Timestamp associado ao pacote. |
| `hash_valid` | 1 bit | Hash Unit | Indica que os metadados provenientes da Hash Unit são válidos. |
| `rd_data` | 16 bits | Flow Table | Dado retornado pela operação de leitura. |
| `rd_valid` | 1 bit | Flow Table | Indica que o dado lido está disponível. |
| `wr_done` | 1 bit | Flow Table | Indica a conclusão da operação de escrita. |
| `fin_done` | 1 bit | Flow Finalizer | Indica a conclusão do processamento pelo Finalizer. |

## 3. Saídas

| Sinal | Largura | Destino | Descrição |
|---|---:|---|---|
| `rd_en` | 1 bit | Flow Table | Solicita uma operação de leitura. |
| `rd_addr` | 21 bits | Flow Table | Endereço utilizado na leitura da Flow Table. |
| `wr_en` | 1 bit | Flow Table | Solicita uma operação de escrita. |
| `wr_addr` | 21 bits | Flow Table | Endereço utilizado na escrita da Flow Table. |
| `wr_data` | 16 bits | Flow Table | Dado a ser escrito na Flow Table. |
| `flow_entry` | 384 bits | Flow Finalizer | Entrada completa do fluxo enviada para extração de features. |
| `fin_valid` | 1 bit | Flow Finalizer | Indica que uma entrada está disponível para processamento pelo Flow Finalizer. |

## 4. Interface com a Flow Table

O Controller controla as operações de leitura e escrita por meio dos sinais `rd_en`, `rd_addr`, `wr_en`, `wr_addr` e `wr_data`.

O sinal `rd_valid` indica quando o dado solicitado está disponível. O sinal `wr_done` indica quando a escrita foi concluída.

Os endereços possuem 21 bits, enquanto os dados de leitura e escrita possuem 16 bits, conforme apresentado na arquitetura.

## 5. Interface com o Flow Finalizer

O Controller encaminha a entrada do fluxo por meio de `flow_entry[383:0]` e sinaliza que ela está disponível para processamento por meio de `fin_valid`.

O sinal `fin_done`, recebido do Flow Finalizer, indica a conclusão do processamento. O Controller utiliza essa indicação para controlar o avanço para a próxima entrada, conforme a sequência de processamento definida.

O Flow Finalizer também apresenta a saída `feature_vector[279:0]`, que não faz parte da interface de entrada ou saída do Controller mostrada no diagrama.

## 6. Funcionamento do Controller

1. Aguarda `hash_valid` para identificar a disponibilidade de novos metadados.
2. Utiliza `hash_index` para localizar a entrada correspondente na Flow Table.
3. Solicita a leitura utilizando `rd_en` e `rd_addr`.
4. Aguarda `rd_valid` para utilizar os dados retornados.
5. Verifica a entrada e determina se deve inicializá-la ou atualizar suas informações.
6. Solicita a escrita por meio de `wr_en`, `wr_addr` e `wr_data`.
7. Aguarda `wr_done` para prosseguir após a conclusão da escrita.
8. Encaminha a entrada completa por `flow_entry` e sinaliza sua disponibilidade por `fin_valid`.
9. Aguarda `fin_done` para reconhecer a conclusão do processamento pelo Flow Finalizer.

## 7. Resumo dos sinais

### Entradas

```text
clk
reset

hash_index[15:0]
flow_key[103:0]
packet_length[15:0]
timestamp[79:0]
hash_valid

rd_data[15:0]
rd_valid
wr_done

fin_done
```

### Saídas

```text
rd_en
rd_addr[20:0]

wr_en
wr_addr[20:0]
wr_data[15:0]

flow_entry[383:0]
fin_valid
```
