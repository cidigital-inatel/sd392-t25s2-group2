# Flow Table Controller

Documento com a especificação funcional do **Flow Table Controller**, responsável por coordenar o processamento dos pacotes, gerenciar a Flow Table e controlar a finalização dos fluxos.

## Conteúdo

* Fluxo de processamento;
* Máquina de estados (FSM);
* Operações MISS, HIT e COLLISION;
* Interfaces com o Data Mover e o Flow Finalizer;
* Controle `valid/ready`;
* Finalização dos fluxos;
* Estrutura e endereçamento da Flow Table.

## Operações

* **MISS:** cria uma nova entrada e inicializa as estatísticas do fluxo.
* **HIT:** atualiza os contadores e o timestamp do fluxo existente.
* **COLLISION:** identifica uma chave diferente na posição consultada, preservando a entrada existente e sinalizando a colisão.

## FSM

Principais estados:

```text
IDLE → FETCH → CHECK
                 ├── MISS → INSERT
                 ├── HIT → UPDATE
                 └── COLLISION

IDLE → FINALIZE_SCAN → FINALIZE_SEND
                            ↓
                       FINALIZE_WAIT
                            ↓
                     FINALIZE_SCAN
                            ↓
                           DONE
```

## Parâmetros principais

| Parâmetro    | Valor               |
| ------------ | ------------------- |
| Flow Key     | 104 bits            |
| Índice Hash  | 16 bits             |
| Flow Table   | 65.536 entradas     |
| Registro     | 512 bits            |
| Organização  | 32 words de 16 bits |
| Packet Count | 32 bits             |
| Byte Count   | 64 bits             |
| Timestamp    | 80 bits             |

Após `pcap_done`, o Controller percorre a Flow Table e encaminha as entradas válidas ao Flow Finalizer, sinalizando `all_flows_done` ao concluir o processamento.
