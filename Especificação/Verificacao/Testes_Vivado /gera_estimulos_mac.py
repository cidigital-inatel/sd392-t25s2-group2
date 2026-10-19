"""Gera o PCAP de teste e, opcionalmente, arquivos TXT de apoio.

Arquivos gerados:

    teste_bia_dani.pcap
        Quadros Ethernet II de teste.

    stream_words.txt
        Estimulo TXT opcional da interface RX do MAC.

    packet_metadata.txt
        Relacao entre o timestamp do PCAP e o timestamp usado na simulacao.

O timestamp nao e colocado em tdata. Ele e usado pela testbench para
reproduzir os intervalos entre pacotes e validar o TSU.
"""

from __future__ import annotations

import struct
from pathlib import Path


try:
    # Funciona quando o programa e executado como arquivo .py no Visual Studio.
    BASE_DIR = Path(__file__).resolve().parent
except NameError:
    # Funciona tambem se o codigo for colado diretamente em uma celula/janela.
    BASE_DIR = Path.cwd()
PCAP_FILE = BASE_DIR / "teste_bia_dani.pcap"
STREAM_FILE = BASE_DIR / "stream_words.txt"
METADATA_FILE = BASE_DIR / "packet_metadata.txt"

# True: cria o PCAP de teste deste projeto.
# False: usa o arquivo indicado em PCAP_FILE sem sobrescreve-lo.
GENERATE_TEST_PCAP = False

# A testbench da Semana 4 le o PCAP diretamente. Portanto, o fluxo principal
# nao precisa criar stream_words.txt nem packet_metadata.txt.
# Altere para True somente se precisar dos arquivos TXT de apoio.
GENERATE_STREAM_FILES = False

WORD_BYTES = 8
DLT_NULL = 0
DLT_EN10MB = 1
DLT_RAW = 101
DLT_IPV4 = 228
DLT_IPV6 = 229

# O PCAP tera timestamps 100 ms separados.
PCAP_FIRST_TIMESTAMP_NS = 1_700_000_000_000_000_000
PCAP_PACKET_GAP_NS = 100_000_000

# Escala documentada para a testbench: 100 ms no PCAP -> 1 us simulado.
# Com clock de 100 MHz, sao 100 ciclos de 10 ns entre inicios de pacotes.
REPLAY_SCALE = 100_000
SIM_CLOCK_PERIOD_NS = 10

DEST_MAC = bytes.fromhex("020000000002")
SOURCE_MAC = bytes.fromhex("020000000001")


def internet_checksum(data: bytes) -> int:
    if len(data) % 2:
        data += b"\x00"

    total = 0
    for index in range(0, len(data), 2):
        total += int.from_bytes(data[index:index + 2], "big")

    while total >> 16:
        total = (total & 0xFFFF) + (total >> 16)

    return (~total) & 0xFFFF


def ip_bytes(address: str) -> bytes:
    return bytes(int(part) for part in address.split("."))


def build_ethernet_frame(source: bytes, destination: bytes, ip_packet: bytes) -> bytes:
    return destination + source + bytes.fromhex("0800") + ip_packet


def build_ipv4_packet(
    source_ip: str,
    destination_ip: str,
    protocol: int,
    payload: bytes,
    identification: int,
) -> bytes:
    source = ip_bytes(source_ip)
    destination = ip_bytes(destination_ip)
    total_length = 20 + len(payload)

    header = struct.pack(
        "!BBHHHBBH4s4s",
        0x45,
        0,
        total_length,
        identification,
        0x4000,
        64,
        protocol,
        0,
        source,
        destination,
    )
    checksum = internet_checksum(header)
    header = struct.pack(
        "!BBHHHBBH4s4s",
        0x45,
        0,
        total_length,
        identification,
        0x4000,
        64,
        protocol,
        checksum,
        source,
        destination,
    )
    return header + payload


def build_tcp_segment(
    source_ip: str,
    destination_ip: str,
    source_port: int,
    destination_port: int,
    sequence: int,
    acknowledgment: int,
    flags: int,
    payload: bytes = b"",
) -> bytes:
    offset_and_reserved = 5 << 4
    window = 0xFFFF

    header = struct.pack(
        "!HHIIBBHHH",
        source_port,
        destination_port,
        sequence,
        acknowledgment,
        offset_and_reserved,
        flags,
        window,
        0,
        0,
    )

    pseudo_header = (
        ip_bytes(source_ip)
        + ip_bytes(destination_ip)
        + bytes([0, 6])
        + struct.pack("!H", len(header) + len(payload))
    )
    checksum = internet_checksum(pseudo_header + header + payload)

    header = struct.pack(
        "!HHIIBBHHH",
        source_port,
        destination_port,
        sequence,
        acknowledgment,
        offset_and_reserved,
        flags,
        window,
        checksum,
        0,
    )
    return header + payload


def build_udp_segment(
    source_ip: str,
    destination_ip: str,
    source_port: int,
    destination_port: int,
    payload: bytes,
) -> bytes:
    length = 8 + len(payload)
    header = struct.pack(
        "!HHHH",
        source_port,
        destination_port,
        length,
        0,
    )
    pseudo_header = (
        ip_bytes(source_ip)
        + ip_bytes(destination_ip)
        + bytes([0, 17])
        + struct.pack("!H", length)
    )
    checksum = internet_checksum(pseudo_header + header + payload)
    if checksum == 0:
        checksum = 0xFFFF

    return struct.pack(
        "!HHHH",
        source_port,
        destination_port,
        length,
        checksum,
    ) + payload


def make_test_frames() -> list[tuple[bytes, str]]:
    client_mac = bytes.fromhex("020000001001")
    server_mac = bytes.fromhex("020000002001")
    client_ip = "192.168.10.10"
    server_ip = "192.168.10.20"
    client_port = 49152
    server_port = 80
    client_isn = 1000
    server_isn = 2000

    http_request = (
        b"GET /index.html HTTP/1.1\r\n"
        b"Host: exemplo.local\r\n"
        b"Connection: close\r\n"
        b"\r\n"
    )
    http_response = (
        b"HTTP/1.1 200 OK\r\n"
        b"Content-Length: 13\r\n"
        b"Connection: close\r\n"
        b"\r\n"
        b"Hello, World!"
    )

    frames: list[tuple[bytes, str]] = []

    def add_tcp(
        source_mac: bytes,
        destination_mac: bytes,
        source_ip: str,
        destination_ip: str,
        source_port: int,
        destination_port: int,
        sequence: int,
        acknowledgment: int,
        flags: int,
        identification: int,
        label: str,
        payload: bytes = b"",
    ) -> None:
        tcp = build_tcp_segment(
            source_ip,
            destination_ip,
            source_port,
            destination_port,
            sequence,
            acknowledgment,
            flags,
            payload,
        )
        ip_packet = build_ipv4_packet(
            source_ip,
            destination_ip,
            6,
            tcp,
            identification,
        )
        frames.append((build_ethernet_frame(source_mac, destination_mac, ip_packet), label))

    add_tcp(
        client_mac, server_mac, client_ip, server_ip,
        client_port, server_port, client_isn, 0, 0x02, 1, "TCP_SYN",
    )
    add_tcp(
        server_mac, client_mac, server_ip, client_ip,
        server_port, client_port, server_isn, client_isn + 1, 0x12, 2, "TCP_SYN_ACK",
    )
    add_tcp(
        client_mac, server_mac, client_ip, server_ip,
        client_port, server_port, client_isn + 1, server_isn + 1, 0x10, 3, "TCP_ACK",
    )
    add_tcp(
        client_mac, server_mac, client_ip, server_ip,
        client_port, server_port, client_isn + 1, server_isn + 1, 0x18, 4,
        "HTTP_REQUEST", http_request,
    )
    add_tcp(
        server_mac, client_mac, server_ip, client_ip,
        server_port, client_port, server_isn + 1,
        client_isn + 1 + len(http_request), 0x18, 5,
        "HTTP_RESPONSE", http_response,
    )

    udp_request = build_udp_segment(
        client_ip, server_ip, 53000, 5000, b"mensagem UDP de teste"
    )
    frames.append((
        build_ethernet_frame(
            client_mac,
            server_mac,
            build_ipv4_packet(client_ip, server_ip, 17, udp_request, 6),
        ),
        "UDP_REQUEST",
    ))

    udp_response = build_udp_segment(
        server_ip, client_ip, 5000, 53000, b"resposta UDP de teste"
    )
    frames.append((
        build_ethernet_frame(
            server_mac,
            client_mac,
            build_ipv4_packet(server_ip, client_ip, 17, udp_response, 7),
        ),
        "UDP_RESPONSE",
    ))

    return frames


def write_pcap(filename: Path, frames: list[tuple[bytes, str]]) -> None:
    """Grava PCAP classico 2.4, little-endian, timestamps em microssegundos.

    Usa somente a biblioteca padrao do Python; nao requer Scapy nem rede.
    """
    with filename.open("wb") as pcap:
        # Cabecalho global: magic, versao, timezone, sigfigs, snaplen, linktype.
        pcap.write(struct.pack(
            "<IHHIIII", 0xA1B2C3D4, 2, 4, 0, 0, 65535, DLT_EN10MB
        ))

        for index, (frame, _label) in enumerate(frames):
            timestamp_ns = PCAP_FIRST_TIMESTAMP_NS + index * PCAP_PACKET_GAP_NS
            seconds = timestamp_ns // 1_000_000_000
            microseconds = (timestamp_ns % 1_000_000_000) // 1_000
            pcap.write(struct.pack(
                "<IIII", seconds, microseconds, len(frame), len(frame)
            ))
            pcap.write(frame)


def read_pcap_records(filename: Path) -> tuple[int, list[tuple[int, bytes]]]:
    """Le registros PCAP classicos e valida os comprimentos dos registros."""
    data = filename.read_bytes()
    if len(data) < 24:
        raise ValueError("PCAP invalido: cabecalho global incompleto.")

    magic_info = {
        b"\xd4\xc3\xb2\xa1": ("<", 1_000_000),
        b"\xa1\xb2\xc3\xd4": (">", 1_000_000),
        b"\x4d\x3c\xb2\xa1": ("<", 1_000_000_000),
        b"\xa1\xb2\x3c\x4d": (">", 1_000_000_000),
    }
    if data[:4] not in magic_info:
        raise ValueError("Formato PCAP classico nao reconhecido; PCAPNG nao e suportado.")

    endian, fraction_scale = magic_info[data[:4]]
    major, minor = struct.unpack_from(endian + "HH", data, 4)
    if (major, minor) != (2, 4):
        raise ValueError(f"Versao PCAP nao suportada: {major}.{minor} (esperado 2.4).")

    snaplen, link_type = struct.unpack_from(endian + "II", data, 16)
    if snaplen == 0:
        raise ValueError("PCAP invalido: snaplen nao pode ser zero.")

    offset = 24
    records: list[tuple[int, bytes]] = []
    record_number = 0
    while offset < len(data):
        remaining = len(data) - offset
        if remaining < 16:
            raise ValueError(
                f"PCAP truncado: cabecalho do registro {record_number + 1} tem {remaining} de 16 bytes."
            )

        seconds, fraction, captured_length, original_length = struct.unpack_from(
            endian + "IIII", data, offset
        )
        offset += 16
        record_number += 1

        max_fraction = 1_000_000_000 if fraction_scale == 1_000_000_000 else 1_000_000
        if fraction >= max_fraction:
            raise ValueError(
                f"Registro {record_number}: fracao de timestamp {fraction} fora do intervalo valido."
            )
        if captured_length == 0:
            raise ValueError(f"Registro {record_number}: captured_length zero.")
        if captured_length > snaplen:
            raise ValueError(
                f"Registro {record_number}: captured_length {captured_length} excede snaplen {snaplen}."
            )
        if original_length < captured_length:
            raise ValueError(
                f"Registro {record_number}: original_length menor que captured_length."
            )
        if offset + captured_length > len(data):
            raise ValueError(f"PCAP truncado durante os dados do registro {record_number}.")

        frame = data[offset:offset + captured_length]
        offset += captured_length
        timestamp_ns = seconds * 1_000_000_000
        timestamp_ns += (fraction * 1_000_000_000) // fraction_scale
        records.append((timestamp_ns, frame))

    return link_type, records


def get_null_family(data: bytes) -> int:
    if len(data) < 4:
        raise ValueError("Pacote DLT_NULL incompleto.")
    known = {2, 24, 28, 30}
    little = int.from_bytes(data[:4], "little")
    big = int.from_bytes(data[:4], "big")
    if little in known:
        return little
    if big in known:
        return big
    raise ValueError(f"Familia DLT_NULL desconhecida: {little}/{big}")


def to_ethernet_ii(data: bytes, link_type: int) -> bytes:
    if link_type == DLT_EN10MB:
        return data

    if link_type == DLT_NULL:
        get_null_family(data)
        ip_packet = data[4:]
    elif link_type in {DLT_RAW, DLT_IPV4, DLT_IPV6}:
        ip_packet = data
    else:
        raise ValueError(f"DLT nao suportado: {link_type}")

    if not ip_packet:
        raise ValueError("Pacote IP vazio.")

    version = ip_packet[0] >> 4
    if version == 4:
        ether_type = bytes.fromhex("0800")
    elif version == 6:
        ether_type = bytes.fromhex("86DD")
    else:
        raise ValueError(f"Versao IP desconhecida: {version}")

    return DEST_MAC + SOURCE_MAC + ether_type + ip_packet


def classify_frame(frame: bytes) -> str:
    if len(frame) < 14:
        return "UNKNOWN"
    if int.from_bytes(frame[12:14], "big") != 0x0800:
        return "ETHERNET_OTHER"
    if len(frame) < 34:
        return "IPV4_SHORT"

    ip_start = 14
    ihl = (frame[ip_start] & 0x0F) * 4
    transport_start = ip_start + ihl
    protocol = frame[ip_start + 9]

    if protocol == 17:
        return "UDP"

    if protocol != 6 or len(frame) < transport_start + 20:
        return f"IP_PROTO_{protocol}"

    flags = frame[transport_start + 13]
    tcp_header_length = ((frame[transport_start + 12] >> 4) & 0x0F) * 4
    payload = frame[transport_start + tcp_header_length:]

    if payload.startswith(b"GET ") or payload.startswith(b"POST "):
        return "HTTP_REQUEST"
    if payload.startswith(b"HTTP/"):
        return "HTTP_RESPONSE"
    if flags == 0x02:
        return "TCP_SYN"
    if flags == 0x12:
        return "TCP_SYN_ACK"
    if flags == 0x10 and not payload:
        return "TCP_ACK"
    return "TCP"


def keep_mask(valid_bytes: int) -> int:
    if not 1 <= valid_bytes <= WORD_BYTES:
        raise ValueError(f"Quantidade de bytes invalida: {valid_bytes}")
    return (1 << valid_bytes) - 1


def to_tdata(block: bytes) -> str:
    padded = block.ljust(WORD_BYTES, b"\x00")
    # O primeiro byte do pacote fica em tdata[7:0].
    return padded[::-1].hex().upper()


def convert_pcap() -> None:
    link_type, records = read_pcap_records(PCAP_FILE)
    if not records:
        raise ValueError("O PCAP nao possui pacotes.")

    first_timestamp_ns = records[0][0]
    packet_count = 0
    word_count = 0

    with STREAM_FILE.open("w", encoding="ascii") as stream, METADATA_FILE.open(
        "w", encoding="ascii"
    ) as metadata:
        stream.write("# tdata tkeep tvalid tlast tuser\n")
        metadata.write(
            "# packet_id timestamp_pcap_ns timestamp_sim_ns frame_bytes words protocol\n"
        )

        for packet_count, (timestamp_ns, captured_data) in enumerate(records, start=1):
            frame = to_ethernet_ii(captured_data, link_type)
            word_total = (len(frame) + WORD_BYTES - 1) // WORD_BYTES
            protocol = classify_frame(frame)

            relative_pcap_ns = timestamp_ns - first_timestamp_ns
            timestamp_sim_ns = (relative_pcap_ns // REPLAY_SCALE)
            timestamp_sim_ns = (
                timestamp_sim_ns // SIM_CLOCK_PERIOD_NS
            ) * SIM_CLOCK_PERIOD_NS

            metadata.write(
                f"{packet_count} {timestamp_ns} {timestamp_sim_ns} "
                f"{len(frame)} {word_total} {protocol}\n"
            )

            print(
                f"Pacote {packet_count}: {protocol} | "
                f"PCAP={timestamp_ns} ns | "
                f"sim={timestamp_sim_ns} ns | "
                f"bytes={len(frame)} | palavras={word_total}"
            )

            for word_index in range(word_total):
                start = word_index * WORD_BYTES
                block = frame[start:start + WORD_BYTES]
                valid_bytes = len(block)
                tdata = to_tdata(block)
                tkeep = keep_mask(valid_bytes)
                tlast = int(word_index == word_total - 1)
                # Para os quadros sinteticos validos, TUSER=1 no ultimo beat.
                # Antes do TLAST, o valor pode permanecer em zero.
                tuser = tlast
                stream.write(
                    f"{tdata} {tkeep:02X} 1 {tlast} {tuser}\n"
                )
                word_count += 1

    print()
    print("Conversao concluida!")
    print(f"PCAP: {PCAP_FILE}")
    print(f"Stream: {STREAM_FILE}")
    print(f"Metadados: {METADATA_FILE}")
    print(f"Pacotes: {packet_count}")
    print(f"Palavras AXI: {word_count}")


def main() -> None:
    if GENERATE_TEST_PCAP:
        frames = make_test_frames()
        write_pcap(PCAP_FILE, frames)
        print(f"PCAP criado: {PCAP_FILE}")
    elif not PCAP_FILE.exists():
        raise FileNotFoundError(
            f"PCAP nao encontrado: {PCAP_FILE}. Coloque o arquivo na pasta do script "
            "ou defina GENERATE_TEST_PCAP = True para criar o PCAP sintetico."
        )

    link_type, records = read_pcap_records(PCAP_FILE)
    if not records:
        raise ValueError("O PCAP esta valido estruturalmente, mas nao contem pacotes.")
    print(f"PCAP validado: {PCAP_FILE}")
    print(f"Link-type: {link_type}; pacotes: {len(records)}")
    for index, (timestamp_ns, frame) in enumerate(records, start=1):
        print(
            f"  Pacote {index}: tipo={classify_frame(to_ethernet_ii(frame, link_type))} "
            f"bytes={len(frame)} timestamp_ns={timestamp_ns}"
        )

    if GENERATE_STREAM_FILES:
        convert_pcap()
    else:
        print("Conversao para TXT desativada: a testbench lera o PCAP diretamente.")


if __name__ == "__main__":
    main()
