# Flow Table Controller

Documento com a especificação funcional do **Flow Table Controller**, responsável por controlar o acesso à Flow Table e o processamento dos fluxos.

## Conteúdo

* Fluxo de processamento;
* Máquina de estados (FSM);
* Operações MISS, HIT e COLLISION;
* Controle `valid/ready`;
* Finalização dos fluxos;
* Interfaces com os demais módulos;
* Estrutura da Flow Table.

## Operações

* **MISS:** cria uma nova entrada na Flow Table.
* **HIT:** atualiza as estatísticas de um fluxo existente.
* **COLLISION:** identifica uma entrada ocupada por outro fluxo e sinaliza a colisão sem sobrescrevê-la.

## FSM

Principais estados:

```text
IDLE → LOOKUP → CHECK
                  ├── MISS → INSERT
                  ├── HIT → UPDATE
                  └── COLLISION
```

Após `pcap_done`, o Controller percorre a Flow Table e encaminha as entradas válidas ao Flow Finalizer.
