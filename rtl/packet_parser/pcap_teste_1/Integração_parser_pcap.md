# Validação do Packet Parser com Leitura Direta de PCAP

## 1. Objetivo

Esta validação teve como objetivo verificar o funcionamento do `packet_parser` utilizando diretamente um arquivo `.pcap` como fonte de estímulos, sem a necessidade de conversão prévia para arquivo `.txt`.

A testbench realiza a leitura dos registros do PCAP, converte os bytes dos pacotes para a interface de entrada do Parser e monitora os metadados produzidos na saída.

O fluxo utilizado foi:

```text
PCAP
  ↓
Testbench
  ↓
TDATA / TKEEP / TVALID / TLAST / TUSER / timestamp
  ↓
Packet Parser
  ↓
src_ip / dst_ip / src_port / dst_port / protocol / packet_length / timestamp / valid
```

---

## 2. Arquivo de entrada

Foi utilizado o arquivo:

```text
teste.pcap
```

Durante a análise do PCAP, foi identificado que os pacotes não possuem cabeçalho Ethernet II de 14 bytes.

Os pacotes iniciam com um padrão semelhante a:

```text
02 00 00 00 45 ...
```

Os quatro primeiros bytes correspondem ao cabeçalho de enlace utilizado em capturas de loopback no formato `DLT_NULL`.

Nesse formato:

```text
02 00 00 00
```

indica a família de protocolo `AF_INET`, ou seja, que o conteúdo seguinte é IPv4.

O byte:

```text
45
```

já corresponde ao primeiro byte do cabeçalho IPv4:

```text
4 = versão IPv4
5 = IHL igual a 5 palavras de 32 bits
```

Portanto, neste PCAP:

```text
bytes 0..3  → cabeçalho DLT_NULL
byte 4      → início do cabeçalho IPv4
```

---

## 3. Parametrização do Parser

O Parser foi parametrizado para permitir a validação tanto de tráfego Ethernet II quanto do PCAP de loopback utilizado nesta etapa.

Foi utilizado o parâmetro:

```systemverilog
parameter int L3_OFFSET = 14;
```

### Modo Ethernet II

```systemverilog
L3_OFFSET = 14
```

Nesse modo, o Parser considera:

```text
Dst MAC     = 6 bytes
Src MAC     = 6 bytes
EtherType   = 2 bytes
IPv4        = inicia no byte 14
```

O EtherType esperado para IPv4 é:

```text
0x0800
```

### Modo DLT_NULL / loopback

```systemverilog
L3_OFFSET = 4
```

Nesse modo, os quatro primeiros bytes são desconsiderados para o parsing de IPv4 e o cabeçalho IP passa a ser interpretado a partir do byte 4.

Para esta validação foi utilizada a configuração:

```systemverilog
.L3_OFFSET(4)
```

---

## 4. Observação sobre a validação Ethernet

Como o PCAP utilizado foi obtido a partir de uma captura em interface de loopback, ele não contém os 14 bytes do cabeçalho Ethernet II.

Consequentemente, esta etapa **não valida o parsing do cabeçalho Ethernet completo nem a identificação do EtherType**.

A lógica referente a Ethernet II permanece disponível no Parser por meio do modo:

```systemverilog
L3_OFFSET = 14
```

A validação desse caminho deverá ser realizada posteriormente utilizando uma captura de tráfego proveniente de uma interface Ethernet, contendo:

```text
Dst MAC | Src MAC | EtherType | IPv4 | TCP/UDP
```

---

## 5. Interface de dados utilizada

A testbench foi ajustada para seguir a organização de bytes utilizada pela frente de verificação.

### TDATA

O primeiro byte do pacote é colocado em:

```text
TDATA[7:0]
```

O segundo byte em:

```text
TDATA[15:8]
```

e assim sucessivamente até:

```text
TDATA[63:56]
```

Portanto:

```text
byte 0 → TDATA[7:0]
byte 1 → TDATA[15:8]
...
byte 7 → TDATA[63:56]
```

---

## 6. TKEEP

O `TKEEP` indica quais bytes de `TDATA` são válidos.

A convenção utilizada é:

```text
1 byte válido   → 8'h01
2 bytes válidos → 8'h03
3 bytes válidos → 8'h07
4 bytes válidos → 8'h0F
5 bytes válidos → 8'h1F
6 bytes válidos → 8'h3F
7 bytes válidos → 8'h7F
8 bytes válidos → 8'hFF
```

Nos beats intermediários são esperados oito bytes válidos:

```text
TKEEP = 8'hFF
```

O `TKEEP` parcial é utilizado no último beat quando o tamanho do pacote não é múltiplo de oito bytes.

---

## 7. Timestamp

O timestamp utilizado segue o formato de 80 bits definido pela frente de verificação:

```text
timestamp[79:32] = Seconds
timestamp[31:0]  = Nanoseconds
```

Exemplo observado durante a simulação:

```text
ts  = 00006aba750019bcc690
sec = 1790604544
ns  = 431802000
```

O Parser captura e encaminha o timestamp associado ao pacote.

---

## 8. Protocolos processados

Nesta etapa, o Parser considera válidos os pacotes:

```text
IPv4 + TCP
IPv4 + UDP
```

Os protocolos são identificados pelo campo `Protocol` do cabeçalho IPv4:

```text
TCP = 6
UDP = 17
```

Pacotes fora do escopo, como IPv6, ICMP e outros protocolos não suportados, não geram `valid`.

---

## 9. Metadados extraídos

Para cada pacote válido, o Parser disponibiliza:

```text
src_ip
dst_ip
src_port
dst_port
protocol
packet_length
timestamp
valid
```

Exemplo de pacote TCP processado:

```text
src_ip        = 7f000001
dst_ip        = 7f000001
src_port      = 65020
dst_port      = 49691
protocol      = 6
packet_length = 40
```

O endereço:

```text
7f000001
```

corresponde a:

```text
127.0.0.1
```

Também foram observados pacotes UDP válidos durante a simulação.

---

## 10. Resultado da simulação

A execução completa apresentou:

```text
PCAP records enviados = 10000
Metadados validos liberados pelo Parser = 7418
```

A testbench processou diretamente os 10.000 registros do PCAP.

Desses registros, 7.418 produziram metadados válidos no Parser, correspondentes aos pacotes IPv4 TCP/UDP suportados pela implementação.

O próprio log da simulação apresentou:

```text
OBS: IPv4/TCP/UDP suportados geram valid;
IPv6/ICMP/outros sao descartados.
```

---

## 11. Exemplos observados

### TCP

```text
src=7f000001
dst=7f000001
sport=65020
dport=49691
proto=6
len=40
```

Também foram observados pacotes pertencentes ao mesmo fluxo com diferentes comprimentos e timestamps.

Como a arquitetura trabalha com fluxos unidirecionais, a inversão de IPs e portas representa outro `flow_key`.

### UDP

Exemplos observados:

```text
src=0a008352
dst=ffffffff
sport=57671
dport=1947
proto=17
len=68
```

e:

```text
src=0a008352
dst=e00000fb
sport=5353
dport=5353
proto=17
```

---

## 12. Finalização no TLAST

O Parser foi ajustado para finalizar o processamento diretamente quando recebe:

```text
TVALID = 1
TLAST  = 1
```

Ao final do pacote:

```text
TLAST
  ↓
validação final
  ↓
valid
  ↓
retorno para IDLE
```

Dessa forma, o módulo fica disponível para receber o início do pacote seguinte já no próximo ciclo de clock.

Essa abordagem evita a perda de pacotes consecutivos em uma interface sem `TREADY`.

---

## 13. Status da validação

| Item | Status |
|---|---|
| Leitura direta do PCAP | PASS |
| Processamento de 10.000 registros | PASS |
| `L3_OFFSET = 4` para DLT_NULL | PASS |
| Organização de bytes em `TDATA` | PASS |
| Convenção de `TKEEP` | PASS |
| Parsing IPv4 | PASS |
| Parsing TCP | PASS |
| Parsing UDP | PASS |
| Extração de IPs | PASS |
| Extração de portas | PASS |
| Extração de `packet_length` | PASS |
| Timestamp Seconds + Nanoseconds | PASS |
| Finalização direta em `TLAST` | PASS |
| Processamento de pacotes consecutivos | PASS |
| Parsing Ethernet II de 14 bytes | PENDENTE DE CAPTURA ETHERNET |
| Validação do EtherType | PENDENTE DE CAPTURA ETHERNET |

---

## 14. Conclusão

A validação demonstrou que o `packet_parser` é capaz de receber diretamente os estímulos gerados a partir do arquivo PCAP, interpretar corretamente pacotes IPv4 TCP/UDP e produzir os metadados necessários para as etapas seguintes da arquitetura.

O uso de `L3_OFFSET = 4` permitiu compatibilizar o Parser com o PCAP de loopback utilizado pela frente de verificação, sem remover o suporte ao formato Ethernet II originalmente previsto para a arquitetura.

A validação do cabeçalho Ethernet II e do campo `EtherType` deverá ser realizada posteriormente utilizando uma captura proveniente de uma interface Ethernet real.

Com os testes atuais, fica validado o caminho:

```text
PCAP → Testbench → Packet Parser → Metadados
```

para o tráfego IPv4 TCP/UDP presente no arquivo utilizado.
