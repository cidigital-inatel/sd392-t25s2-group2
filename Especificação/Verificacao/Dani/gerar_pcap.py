import time
from scapy.all import Ether, IP, UDP, Raw, wrpcap


def gerar_pcap_exemplo(nome_arquivo="exemplo.pcap"):
    tempo_base = time.time()

    # Pacote 1: Pacote Ethernet/IP/UDP completo
    pkt1 = Ether() / IP(dst="192.168.1.10") / UDP(dport=80) / Raw(load=b"Hello Packet Parser!")
    pkt1.time = tempo_base

    # Pacote 2: Pacote pequeno de 9 bytes (1 word de 64 bits cheia + 1 byte sobra)
    pkt2 = Raw(load=b"123456789")
    pkt2.time = tempo_base + 0.001  # 1 ms depois

    # Pacote 3: Pacote de 27 bytes (3 words cheias + 3 bytes sobra)
    pkt3 = Raw(load=b"123456789012345678901234567")
    pkt3.time = tempo_base + 0.002  # 2 ms depois

    pacotes = [pkt1, pkt2, pkt3]
    wrpcap(nome_arquivo, pacotes)
    print(f"Arquivo '{nome_arquivo}' gerado com sucesso contendo {len(pacotes)} pacotes.")


if __name__ == "__main__":
    gerar_pcap_exemplo()
