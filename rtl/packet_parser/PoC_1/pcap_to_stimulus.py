# -*- coding: utf-8 -*-
from scapy.all import rdpcap

PCAP_FILE = "basic_tcp.pcap"
OUTPUT_FILE = "input_stream.txt"
WORD_BYTES = 8
TIMESTAMP_BITS = 80
TIMESTAMP_HEX_DIGITS = 20

def make_keep(valid_bytes: int) -> int:
    if not 0 <= valid_bytes <= WORD_BYTES:
        raise ValueError("valid_bytes deve estar entre 0 e 8")
    if valid_bytes == 0:
        return 0
    return ((1 << valid_bytes) - 1) << (WORD_BYTES - valid_bytes)

def packet_timestamp_to_ns(pkt) -> int:
    return int(pkt.time * 1_000_000_000)

def packet_to_stream(pkt):
    raw = bytes(pkt)
    timestamp_ns = packet_timestamp_to_ns(pkt)
    if timestamp_ns >= (1 << TIMESTAMP_BITS):
        raise ValueError("Timestamp nao cabe em 80 bits.")

    rows = []
    for offset in range(0, len(raw), WORD_BYTES):
        chunk = raw[offset:offset + WORD_BYTES]
        valid_bytes = len(chunk)
        padded = chunk.ljust(WORD_BYTES, b"\x00")
        tdata = padded.hex().upper()
        tkeep = make_keep(valid_bytes)
        tvalid = 1
        tlast = 1 if offset + WORD_BYTES >= len(raw) else 0
        tuser = 1 if tlast else 0
        timestamp_hex = f"{timestamp_ns:020X}"
        rows.append((tdata, tkeep, tvalid, tlast, tuser, timestamp_hex))
    return rows

def main():
    packets = rdpcap(PCAP_FILE)
    with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
        f.write("TDATA TKEEP TVALID TLAST TUSER TIMESTAMP_HEX\n")
        for pkt in packets:
            for tdata, tkeep, tvalid, tlast, tuser, ts_hex in packet_to_stream(pkt):
                f.write(f"{tdata} {tkeep:02X} {tvalid} {tlast} {tuser} {ts_hex}\n")
    print(f"{len(packets)} pacote(s) convertido(s).")
    print(f"Arquivo {OUTPUT_FILE} criado com sucesso.")
    print("Timestamp: 80 bits em nanossegundos.")

if __name__ == "__main__":
    main()
