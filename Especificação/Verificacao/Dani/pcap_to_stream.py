
import argparse
import logging
from decimal import Decimal
from pathlib import Path
from scapy.all import PcapReader, raw

WORD_BYTES = 8
TUSER_QUADRO_VALIDO = 1


def timestamp_to_ns(timestamp) -> int:
    return int(Decimal(str(timestamp)) * Decimal("1000000000"))


def keep_mask(valid_bytes: int, word_bytes: int = WORD_BYTES) -> int:
    if valid_bytes < 1 or valid_bytes > word_bytes:
        raise ValueError(f"Quantidade de bytes inválida: {valid_bytes}")
    return (1 << valid_bytes) - 1


def data_to_axi_hex(block: bytes, word_bytes: int = WORD_BYTES) -> str:
    padded_block = block.ljust(word_bytes, b"\x00")
    return padded_block[::-1].hex().upper()


def hex_to_bytes(data_hex: str, keep_hex: str) -> bytes:
    """Reconstrói os bytes originais de uma word a partir de data/keep -- usado na validação."""
    valid_bytes = bin(int(keep_hex, 16)).count("1")
    raw_bytes = bytes.fromhex(data_hex)[::-1]
    return raw_bytes[:valid_bytes]


def convert(pcap_path: Path, output_path: Path):
    packet_count = 0
    word_count = 0
    empty_count = 0
    pcap_path = Path(pcap_path)

    if not pcap_path.exists():
        raise FileNotFoundError(f"Arquivo PCAP não encontrado: {pcap_path}")

    with PcapReader(str(pcap_path)) as pcap, open(output_path, "w") as output:
        output.write("# timestamp_ns data valid sop eop keep tuser\n")

        for index, packet in enumerate(pcap):
            data_bytes = raw(packet)
            if not data_bytes:
                empty_count += 1
                logging.warning("Pacote %d vazio/descartado (sem bytes brutos).", index)
                continue

            packet_count += 1
            timestamp_ns = timestamp_to_ns(packet.time)
            number_of_words = (len(data_bytes) + WORD_BYTES - 1) // WORD_BYTES
            reconstructed = bytearray()

            for word_index in range(number_of_words):
                start = word_index * WORD_BYTES
                block = data_bytes[start:start + WORD_BYTES]
                valid_bytes = len(block)
                data_hex = data_to_axi_hex(block)
                sop = int(word_index == 0)
                eop = int(word_index == number_of_words - 1)
                keep_hex = f"{keep_mask(valid_bytes):02X}"

                output.write(
                    f"{timestamp_ns} {data_hex} 1 {sop} {eop} {keep_hex} {TUSER_QUADRO_VALIDO}\n"
                )
                word_count += 1
                reconstructed.extend(hex_to_bytes(data_hex, keep_hex))

            if bytes(reconstructed) != data_bytes:
                raise AssertionError(
                    f"Falha na validação do pacote {index}: bytes reconstruídos "
                    f"não coincidem com o PCAP original."
                )

    return packet_count, word_count, empty_count


def main():
    parser = argparse.ArgumentParser(description="Converte um PCAP em stream_words.txt.")
    parser.add_argument("--pcap", required=True, type=Path, help="Arquivo PCAP de entrada")
    parser.add_argument("--output", required=True, type=Path, help="Arquivo stream_words.txt de saída")
    parser.add_argument("--verbose", action="store_true", help="Exibe avisos de pacotes vazios")

    args = parser.parse_args()
    logging.basicConfig(
        level=logging.WARNING if args.verbose else logging.ERROR,
        format="%(levelname)s: %(message)s",
    )

    try:
        packet_count, word_count, empty_count = convert(args.pcap, args.output)
    except (FileNotFoundError, AssertionError) as exc:
        print(f"Erro: {exc}")
        raise SystemExit(1)

    print("Conversão concluída e validada (bytes reconstruídos == PCAP original).")
    print("Pacotes convertidos:", packet_count)
    print("Pacotes vazios/descartados:", empty_count)
    print("Palavras geradas:", word_count)
    print("Arquivo:", args.output)


if __name__ == "__main__":
    main()
