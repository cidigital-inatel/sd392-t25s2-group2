# -*- coding: utf-8 -*-
"""
Converte um PCAP em estimulos para a interface MAC RX do Packet Parser.

Formato de saida:
    TDATA TKEEP TVALID TLAST TUSER TIMESTAMP

Unidade do TIMESTAMP:
    microssegundos inteiros (us)

Convencoes:
- TDATA: 64 bits, 8 bytes por ciclo;
- primeiro byte do pacote em TDATA[63:56];
- TKEEP[7] corresponde a TDATA[63:56];
- TVALID = 1 em cada transferencia com dados;
- TLAST = 1 apenas na ultima transferencia do quadro;
- TUSER = 1 na ultima transferencia para indicar quadro valido;
- timestamp obtido diretamente do registro PCAP.

Dependencia:
    pip install scapy
"""

from scapy.all import rdpcap

PCAP_FILE = "basic_tcp.pcap"
OUTPUT_FILE = "input_stream.txt"
WORD_BYTES = 8


def make_keep(valid_bytes: int) -> int:
    if not 0 <= valid_bytes <= WORD_BYTES:
        raise ValueError("valid_bytes deve estar entre 0 e 8")

    if valid_bytes == 0:
        return 0

    # Bytes validos ocupam as posicoes mais significativas de TDATA.
    return ((1 << valid_bytes) - 1) << (WORD_BYTES - valid_bytes)


def packet_timestamp_to_us(pkt) -> int:
    """
    Converte o timestamp do PCAP para microssegundos inteiros.

    Evita conversao intermediaria para float para preservar a precisao
    fornecida pelo tipo de timestamp utilizado pelo Scapy.
    """
    return int(pkt.time * 1_000_000)


def packet_to_stream(pkt):
    raw = bytes(pkt)
    timestamp_us = packet_timestamp_to_us(pkt)
    rows = []

    for offset in range(0, len(raw), WORD_BYTES):
        chunk = raw[offset:offset + WORD_BYTES]
        valid_bytes = len(chunk)

        padded = chunk.ljust(WORD_BYTES, b"\x00")

        tdata = padded.hex().upper()
        tkeep = make_keep(valid_bytes)
        tvalid = 1
        tlast = 1 if offset + WORD_BYTES >= len(raw) else 0

        # Nesta PoC, o quadro do PCAP e considerado valido.
        # TUSER e relevante ao final do quadro.
        tuser = 1 if tlast else 0

        rows.append(
            (tdata, tkeep, tvalid, tlast, tuser, timestamp_us)
        )

    return rows


def main():
    packets = rdpcap(PCAP_FILE)

    with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
        f.write("TDATA TKEEP TVALID TLAST TUSER TIMESTAMP\n")

        for pkt in packets:
            for tdata, tkeep, tvalid, tlast, tuser, timestamp_us in packet_to_stream(pkt):
                f.write(
                    f"{tdata} "
                    f"{tkeep:02X} "
                    f"{tvalid} "
                    f"{tlast} "
                    f"{tuser} "
                    f"{timestamp_us}\n"
                )

    print(f"{len(packets)} pacote(s) convertido(s).")
    print(f"Arquivo {OUTPUT_FILE} criado com sucesso.")
    print("Unidade do timestamp: microssegundos (us).")


if __name__ == "__main__":
    main()
