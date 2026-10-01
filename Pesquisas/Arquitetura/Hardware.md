# Pesquisa da Parte de Hardware

Documento com levantamento bibliográfico para apoiar o desenvolvimento da arquitetura em FPGA para processamento de tráfego TCP/IP e extração de features para IDS baseado em Machine Learning.

## Conteúdo

* Recepção e parsing de pacotes;
* Extração de features em FPGA;
* Identificação e manutenção dos fluxos;
* Armazenamento e estruturas de hash;
* Finalização dos fluxos;
* Desafios de implementação em hardware.

## Principais referências

* Fakernet — processamento TCP/UDP em FPGA;
* FPGA UDP Parser MII — parsing de Ethernet/IPv4/UDP;
* Blue Ethernet — processamento baseado em `valid/ready`;
* Low-Latency Modular Packet Header Parser — arquitetura pipeline;
* FPGA Flow Monitor — identificação e armazenamento de flows;
* A Modular System for FPGA-Based TCP Flow Processing — processamento stateful de flows.

## Aplicação no projeto

A pesquisa serve como base para as decisões de arquitetura relacionadas ao **Packet Parser, Flow Identification, Flow Table, extração incremental de features e processamento em pipeline**.
