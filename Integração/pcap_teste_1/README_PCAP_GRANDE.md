# Campanha PCAP grande — ponta a ponta

Teste:
PCAP (`teste.pcap`, DLT_NULL) -> Parser -> FIU -> Hash -> Controller -> Flow Table -> Finalizer.

Configuração inicial:
- primeiros 10.000 registros;
- `L3_OFFSET=4`;
- timestamp 48 bits segundos + 32 bits nanossegundos;
- 80 clocks de intervalo entre quadros;
- varredura completa de 65.536 entradas;
- saída `features_pcap_grande.csv`.

A campanha anterior do Parser observou 7.418 `valid` nos primeiros 10.000 registros.
A testbench emite `WARN` se a contagem atual diferir, e `FAIL` se a quantidade de
lookups concluídos não for igual à quantidade de `valid` do Parser.

O CSV é gerado no diretório de trabalho do ModelSim.
