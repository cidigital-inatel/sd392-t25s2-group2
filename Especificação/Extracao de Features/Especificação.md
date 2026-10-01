# Especificação da Arquitetura de Hardware

Documento com a especificação inicial da arquitetura em FPGA para processamento de tráfego TCP/IP e extração de features para um sistema IDS baseado em Machine Learning.

## Conteúdo

* Arquitetura dos módulos;
* Packet Parser;
* Flow Identification;
* Hash Unit;
* Flow Table;
* Flow Table Controller;
* Feature Update Unit;
* Flow Finalizer;
* Interfaces `valid/ready`;
* Critérios de aceitação.

## Parâmetros principais

| Parâmetro    | Valor                              |
| ------------ | ---------------------------------- |
| Protocolo    | IPv4                               |
| Transporte   | TCP/UDP                            |
| Flow Key     | 104 bits                           |
| Flow Table   | 32 entradas                        |
| Registro     | 297 bits                           |
| Packet Count | 24 bits                            |
| Byte Count   | 40 bits                            |
| Timestamp    | 64 bits                            |
| Features     | Packet Count, Byte Count, Duration |

A identificação dos fluxos utiliza uma 5-tupla: Source IP, Destination IP, Source Port, Destination Port e Protocol.
