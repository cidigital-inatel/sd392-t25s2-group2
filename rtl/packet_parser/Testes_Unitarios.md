# Validação Funcional do Packet Parser

## 1. Objetivo

Esta etapa tem como objetivo ampliar a validação funcional do **Packet Parser** antes de sua integração com o **Flow Identification Unit**.

A primeira PoC validou o processamento de um pacote IPv4/TCP conhecido. A próxima etapa passa a abranger os principais caminhos válidos, casos de descarte, situações de borda e operação contínua do Parser.

A interface de saída adotará a nomenclatura padronizada:

```text
src_ip[31:0]
dst_ip[31:0]
src_port[15:0]
dst_port[15:0]
protocol[7:0]
packet_length[15:0]
timestamp[79:0]
valid
```

O sinal anteriormente denominado `metadata_valid` será padronizado como:

```text
valid
```

O sinal `valid` deverá permanecer ativo durante um único ciclo quando os metadados de um pacote aceito estiverem completos e disponíveis.

---

## 2. Tabela completa de testes unitários

| ID | Cenário | Objetivo | Resultado esperado | Critério de aprovação |
|---|---|---|---|---|
| **UT-01** | IPv4 + TCP válido, `IHL = 5` | Confirmar o caminho funcional TCP já utilizado na primeira PoC | IPs, portas, protocolo, `packet_length` e timestamp corretos; `valid = 1` | Todos os campos corretos e apenas um pulso de `valid` |
| **UT-02** | IPv4 + UDP válido, `IHL = 5` | Validar o caminho UDP da FSM | `protocol = 17`, portas UDP corretas e `valid = 1` | Metadados corretos e ausência de descarte |
| **UT-03** | IPv4 com `IHL > 5` | Validar o cálculo dinâmico do início da camada de transporte | `transport_offset = 14 + (IHL × 4)` e portas extraídas na posição correta | Metadados corretos mesmo com opções IPv4 |
| **UT-04** | Protocolo IPv4 não suportado | Validar descarte de protocolos diferentes de TCP e UDP | `valid = 0` e retorno da FSM ao `IDLE` | Nenhum conjunto de metadados é liberado |
| **UT-05** | EtherType diferente de `0x0800` | Validar descarte de quadros não IPv4 | `valid = 0` e quadro consumido corretamente | FSM retorna ao `IDLE` sem travamento |
| **UT-06** | IPv4 fragmentado | Validar a política de descarte quando `MF = 1` ou `Fragment Offset != 0` | `drop_packet = 1` e `valid = 0` | Nenhum metadado válido é produzido |
| **UT-07** | `TUSER = 0` no final do quadro | Validar a indicação de quadro inválido fornecida pela interface MAC | `valid = 0` | Parser descarta o quadro e retorna ao `IDLE` |
| **UT-08** | Último beat parcial com `TKEEP` | Validar a interpretação correta dos bytes válidos da última palavra | Somente os bytes marcados por `TKEEP` são considerados | Contagem e parsing permanecem corretos |
| **UT-09** | Dois pacotes válidos consecutivos | Validar operação sem reset entre pacotes | Dois pulsos independentes de `valid` | Cada pacote gera somente seus próprios metadados |
| **UT-10** | TCP seguido de UDP | Verificar ausência de resíduos entre pacotes de protocolos diferentes | Primeira saída TCP e segunda saída UDP, ambas corretas | Dados do primeiro pacote não contaminam o segundo |
| **UT-11** | Reset durante o recebimento de um quadro | Verificar o comportamento da FSM e dos registradores internos diante de reset durante processamento | `valid = 0`, FSM retorna ao `IDLE` e o próximo pacote pode ser processado normalmente | Nenhum metadado parcial é liberado e o Parser se recupera corretamente |
| **UT-12** | IPv4 com `IHL < 5` | Validar rejeição de um cabeçalho IPv4 inválido | Pacote descartado e `valid = 0` | Nenhum metadado válido é produzido |
| **UT-13** | IPv4 com `IHL = 15` | Testar o maior cabeçalho IPv4 permitido | `transport_offset = 14 + 60 = 74` e portas extraídas corretamente | Parser processa corretamente o maior IHL permitido |
| **UT-14** | Quadro truncado com `TLAST` antecipado | Verificar o comportamento quando o quadro termina antes da obtenção de todos os campos necessários | Descarte, `valid = 0` e retorno ao `IDLE` | Nenhum metadado incompleto é liberado |
| **UT-15** | Pacotes consecutivos sem ciclo ocioso | Validar operação contínua quando o primeiro beat do próximo quadro chega imediatamente após o `TLAST` do anterior | Cada quadro é reconhecido separadamente e produz seu próprio pulso de `valid` | Nenhum pacote é perdido e não há mistura de dados |
| **UT-16** | `TKEEP` parcial em posição crítica | Verificar se bytes marcados como inválidos não são interpretados como parte dos cabeçalhos | Pacote processado corretamente ou descartado conforme os campos disponíveis | Nenhum byte inválido influencia os metadados |
| **UT-17** | Timestamps diferentes em pacotes consecutivos | Confirmar que o timestamp do pacote anterior não permanece armazenado indevidamente | Cada saída apresenta exclusivamente o timestamp associado ao pacote correspondente | Nenhuma contaminação temporal entre pacotes |

---

## 3. Detalhamento dos grupos de teste

### 3.1 Caminhos válidos

Os primeiros testes devem validar os caminhos funcionais previstos no escopo atual:

```text
UT-01 — IPv4 + TCP
UT-02 — IPv4 + UDP
UT-03 — IPv4 com IHL > 5
UT-13 — IPv4 com IHL = 15
```

Esses casos verificam se o Parser consegue extrair corretamente os metadados em diferentes configurações válidas do cabeçalho IPv4.

Para `IHL = 5`:

```text
IPv4 Header Length = 20 bytes
transport_offset   = 14 + 20
                   = 34 bytes
```

Para `IHL = 15`:

```text
IPv4 Header Length = 60 bytes
transport_offset   = 14 + 60
                   = 74 bytes
```

---

### 3.2 Casos de descarte

Os testes de descarte deverão comprovar que quadros fora do escopo ou inválidos não geram metadados válidos:

```text
UT-04 — protocolo não suportado
UT-05 — EtherType não IPv4
UT-06 — IPv4 fragmentado
UT-07 — TUSER inválido
UT-12 — IHL inválido
UT-14 — quadro truncado
```

Em todos esses casos, o comportamento esperado é:

```text
valid = 0
```

e retorno seguro da FSM ao estado:

```text
IDLE
```

---

### 3.3 Robustez da interface

Os testes relacionados à interface devem verificar principalmente o tratamento correto de `TKEEP`, `TLAST` e das condições de término do quadro:

```text
UT-08 — último beat parcial
UT-14 — TLAST antecipado
UT-16 — TKEEP parcial em posição crítica
```

O Parser deve considerar somente bytes efetivamente válidos, evitando que preenchimentos ou bytes mascarados sejam utilizados durante a extração dos campos.

---

### 3.4 Operação contínua

A validação também deverá incluir pacotes enviados em sequência:

```text
UT-09 — dois pacotes consecutivos
UT-10 — TCP seguido de UDP
UT-15 — pacotes consecutivos sem ciclo ocioso
UT-17 — timestamps diferentes
```

No caso mais crítico, o comportamento esperado é:

```text
último beat do pacote 1
TVALID = 1
TLAST  = 1
        ↓
ciclo seguinte
        ↓
primeiro beat do pacote 2
TVALID = 1
TLAST  = 0
```

O Parser deve reconhecer corretamente o início do novo quadro sem depender de um ciclo com `TVALID = 0`.

---

### 3.5 Reset

O teste `UT-11` deverá validar o comportamento do Parser quando o reset ocorrer durante o recebimento de um quadro.

O comportamento esperado é:

```text
reset
  ↓
FSM → IDLE
  ↓
valid = 0
  ↓
registradores internos reinicializados
  ↓
próximo quadro processado normalmente
```

Nenhum conjunto parcial de metadados deve ser liberado após o reset.

---

## 4. Critérios gerais de aprovação

A validação funcional do Packet Parser será considerada satisfatória quando:

- os valores extraídos coincidirem com os campos presentes nos pacotes de entrada;
- `valid` permanecer ativo por apenas um ciclo para cada pacote aceito;
- pacotes descartados não produzirem pulso de `valid`;
- a FSM retornar corretamente ao estado `IDLE` após processamento válido, descarte ou reset;
- o Parser operar com pacotes consecutivos sem necessidade de reset;
- o timestamp de 80 bits for preservado corretamente;
- os bytes inválidos indicados por `TKEEP` não interferirem na extração;
- não houver contaminação de metadados entre pacotes;
- os resultados automáticos do testbench forem compatíveis com o comportamento observado na Wave.

---

## 5. Resultado esperado da etapa

Após a execução dos testes unitários, deverá ser possível consolidar uma matriz final de resultados:

| ID | Teste | Resultado |
|---|---|---|
| UT-01 | IPv4 + TCP válido | Pendente |
| UT-02 | IPv4 + UDP válido | Pendente |
| UT-03 | IPv4 com IHL > 5 | Pendente |
| UT-04 | Protocolo não suportado | Pendente |
| UT-05 | EtherType não IPv4 | Pendente |
| UT-06 | IPv4 fragmentado | Pendente |
| UT-07 | TUSER inválido | Pendente |
| UT-08 | Último beat parcial | Pendente |
| UT-09 | Dois pacotes consecutivos | Pendente |
| UT-10 | TCP seguido de UDP | Pendente |
| UT-11 | Reset durante o quadro | Pendente |
| UT-12 | IHL < 5 | Pendente |
| UT-13 | IHL = 15 | Pendente |
| UT-14 | Quadro truncado | Pendente |
| UT-15 | Pacotes sem ciclo ocioso | Pendente |
| UT-16 | TKEEP parcial em posição crítica | Pendente |
| UT-17 | Timestamps diferentes | Pendente |

Quando todos os casos previstos apresentarem o comportamento esperado, o **Packet Parser** poderá ser considerado funcionalmente validado para o escopo atual e preparado para integração com o **Flow Identification Unit**.
