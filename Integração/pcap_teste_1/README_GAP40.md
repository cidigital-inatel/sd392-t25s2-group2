# Campanha PCAP grande — GAP 40 clocks — top unificado

## Alterações desta campanha

1. O intervalo entre quadros foi reduzido de **80 para 40 clocks**.
2. Os dois níveis de `top` foram unificados em:
   `top_extracao_features_com_parser.sv`.
3. O top único instancia diretamente:
   Packet Parser -> FIU/Hash -> Controller -> Flow Table -> Flow Finalizer.
4. A testbench continua processando os primeiros 10.000 registros de `teste.pcap`.
5. O CSV desta campanha é:
   `features_pcap_grande_gap40.csv`.

## Referência GAP 80

- Registros: 10.000
- Parser valid: 7.418
- Lookups: 7.418
- MISS: 1.048
- HIT: 6.348
- COLLISION: 22
- Features: 1.048

O teste GAP 40 deve ser comparado diretamente com esses valores.

## Critério principal

Se `lookup_count == parser_valid_count`, não houve perda entre Parser e Controller.
Caso os resultados de MISS/HIT/COLLISION/features também coincidam com GAP 80,
a campanha preservou integralmente o comportamento funcional com metade do intervalo.
