# -*- coding: utf-8 -*-
"""
Cria um PCAP deterministico para a primeira PoC do Packet Parser.

O timestamp do pacote e fixado em 1.234567 s, equivalente a:
    1_234_567 microssegundos

Isso permite conferir automaticamente o timestamp no testbench.

Dependencia:
    pip install scapy
"""

from scapy.all import Ether, IP, TCP, wrpcap

PCAP_FILE = "basic_tcp.pcap"
TEST_TIMESTAMP_US = 1_234_567


def build_test_packet():
    pkt = (
        Ether(
            src="00:11:22:33:44:55",
            dst="66:77:88:99:aa:bb"
        )
        /
        IP(
            src="192.168.1.10",
            dst="8.8.8.8",
            ttl=64
        )
        /
        TCP(
            sport=52100,
            dport=443,
            flags="S"
        )
    )

    # Scapy grava pkt.time no timestamp do registro PCAP.
    pkt.time = TEST_TIMESTAMP_US / 1_000_000

    return pkt


def main():
    pkt = build_test_packet()
    wrpcap(PCAP_FILE, [pkt])

    print(f"Arquivo {PCAP_FILE} criado com sucesso.")
    print(f"Timestamp do pacote: {TEST_TIMESTAMP_US} us")
    print()
    print("RESULTADO ESPERADO")
    print("------------------")
    print("src_ip        =", pkt[IP].src)
    print("dst_ip        =", pkt[IP].dst)
    print("protocol      =", pkt[IP].proto)
    print("src_port      =", pkt[TCP].sport)
    print("dst_port      =", pkt[TCP].dport)
    print("packet_length =", len(bytes(pkt[IP])))
    print("timestamp     =", TEST_TIMESTAMP_US, "us")


if __name__ == "__main__":
    main()
