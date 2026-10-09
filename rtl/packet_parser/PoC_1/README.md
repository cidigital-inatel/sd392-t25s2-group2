# Relatório de Desenvolvimento — Primeira PoC do Packet Parser

## 1. Objetivo da atividade

Nesta etapa foram desenvolvidos os arquivos necessários para estruturar e validar a primeira prova de conceito funcional do **Packet Parser** no ambiente de simulação.

O trabalho do dia resultou na criação de:

- `packet_parser.sv`;
- `packet_parser_tb.sv`;
- `create_test_pcap.py`;
- `pcap_to_stimulus.py`;
- `input_stream.txt`.

Também foi realizada a simulação completa no ModelSim, com validação automática dos metadados extraídos.

---

## 2. `create_test_pcap.py`

Foi desenvolvido um script Python responsável por criar um pacote TCP conhecido e armazená-lo em um arquivo PCAP.

O pacote utilizado na PoC possui:

```text
src_ip   = 192.168.1.10
dst_ip   = 8.8.8.8
src_port = 52100
dst_port = 443
protocol = TCP
```

O script gera:

```text
basic_tcp.pcap
```

Para tornar a simulação reproduzível, o timestamp do pacote foi fixado em:

```text
1.234567 s
=
1_234_567 us
```

Esse arquivo serve como entrada controlada para o restante do fluxo de verificação.

---

## 3. `pcap_to_stimulus.py`

Foi desenvolvido um segundo script Python para converter o conteúdo do PCAP em estímulos compatíveis com a interface de entrada do Packet Parser.

O fluxo é:

```text
basic_tcp.pcap
        ↓
pcap_to_stimulus.py
        ↓
input_stream.txt
```

O arquivo gerado utiliza o formato:

```text
TDATA TKEEP TVALID TLAST TUSER TIMESTAMP
```

A interface considera palavras de 64 bits, com até 8 bytes por ciclo.

Para a última transferência do pacote, como existem seis bytes válidos, foi utilizado:

```text
TKEEP = FC
```

O timestamp do PCAP é convertido para microssegundos inteiros e incluído em cada linha do arquivo de estímulos.

---

## 4. `input_stream.txt`

Foi gerado o arquivo de estímulos que representa o pacote TCP no formato utilizado pelo testbench.

Conteúdo utilizado na simulação:

```text
TDATA TKEEP TVALID TLAST TUSER TIMESTAMP
66778899AABB0011 FF 1 0 0 1234567
2233445508004500 FF 1 0 0 1234567
0028000100004006 FF 1 0 0 1234567
A90DC0A8010A0808 FF 1 0 0 1234567
0808CB8401BB0000 FF 1 0 0 1234567
0000000000005002 FF 1 0 0 1234567
2000F0E000000000 FC 1 1 1 1234567
```

Esse arquivo é lido diretamente pelo testbench durante a simulação.

---

## 5. `packet_parser.sv`

Foi desenvolvido o módulo RTL responsável pela extração dos metadados do quadro recebido.

A interface de entrada utiliza:

```text
TDATA
TKEEP
TVALID
TLAST
TUSER
timestamp_in
```

O módulo processa:

- Ethernet II;
- IPv4;
- TCP;
- UDP.

Os metadados disponibilizados são:

```text
src_ip
dst_ip
src_port
dst_port
protocol
packet_length
timestamp
metadata_valid
```

O Parser também realiza:

- identificação de EtherType `0x0800`;
- verificação de IPv4;
- leitura dinâmica do campo IHL;
- cálculo de `transport_offset`;
- extração das portas TCP/UDP;
- leitura do IPv4 Total Length;
- detecção de fragmentação IPv4;
- descarte de pacotes fora do escopo;
- geração de um pulso de `metadata_valid`.

O timestamp é capturado no início do quadro por meio de `timestamp_in`.

---

## 6. `packet_parser_tb.sv`

Foi desenvolvido o testbench responsável por aplicar os estímulos ao Packet Parser e validar automaticamente os resultados.

O testbench:

- gera o clock;
- aplica o reset;
- abre `input_stream.txt`;
- descarta a linha de cabeçalho;
- lê os seis campos de cada transferência;
- aplica os sinais ao DUT;
- aguarda o pulso de `metadata_valid`;
- compara as saídas obtidas com os valores esperados.

As variáveis `file_tdata`, `file_tkeep`, `file_tvalid`, `file_tlast`, `file_tuser` e `file_timestamp` armazenam temporariamente os valores lidos do arquivo antes de serem aplicados ao DUT.

A variável `header_line` é utilizada apenas para consumir a primeira linha textual:

```text
TDATA TKEEP TVALID TLAST TUSER TIMESTAMP
```

O timestamp esperado também é obtido do próprio arquivo de estímulos, evitando um valor fixo independente do PCAP.

---

## 7. Resultado da simulação

```

A simulação foi executada com sucesso no **ModelSim - Intel FPGA Edition 2021.1**.

A validação automática confirmou a extração correta dos metadados do pacote TCP

<p align="center">
  <img src="docs/images/transcript_packet_parser.png"
       alt="Resultado da simulação do Packet Parser no ModelSim"
       width="900">
</p>

Os valores correspondem a:

```text
src_ip        = 192.168.1.10
dst_ip        = 8.8.8.8
src_port      = 52100
dst_port      = 443
protocol      = TCP
packet_length = 40 bytes
timestamp     = 1_234_567 us
```

---

## 8. Verificação da Wave

A Wave foi utilizada para verificar o comportamento temporal da interface e os principais sinais internos do Packet Parser.

<p align="center">
  <img src="docs/images/wave_packet_parser.png"
       alt="Wave da simulação do Packet Parser no ModelSim"
       width="1100">
</p>


A análise da Wave confirmou:
- reconhecimento do quadro IPv4;
- IHL = 5;
- cálculo de transport_offset = 34;
- processamento de 54 bytes do quadro;
- drop_packet = 0;
- geração do pulso de metadata_valid;
- retorno da FSM ao estado IDLE após a liberação dos metadados.


A sequência final observada na FSM foi:

```text
CHECK_FRAME
      ↓
OUTPUT_STATE
      ↓
IDLE
```

No estado `OUTPUT_STATE`, `metadata_valid` é ativado durante um ciclo para indicar que os metadados estão completos e disponíveis para o próximo módulo.

Em seguida, o Parser retorna para `IDLE`, ficando pronto para receber um novo pacote.

---

## 9. Resultado da atividade

Ao final desta etapa foi validado o caminho completo:

```text
create_test_pcap.py
        ↓
basic_tcp.pcap
        ↓
pcap_to_stimulus.py
        ↓
input_stream.txt
        ↓
packet_parser_tb.sv
        ↓
packet_parser.sv
        ↓
metadados extraídos corretamente
```

A primeira PoC do Packet Parser encontra-se funcional para o pacote TCP utilizado no teste e servirá como base para os próximos casos de verificação e para a futura integração com os demais módulos da etapa de Extração de Metadados.
