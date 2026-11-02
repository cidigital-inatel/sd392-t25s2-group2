#!/usr/bin/env python3
"""Gera PCAP clássico P01-P14 conforme README_Trafego_Referencia_Validacao_Parser_Features.md.

PCAP: Ethernet II (DLT_EN10MB), little-endian, timestamps em microssegundos.
O testbench associa TUSER=0 ao P12 porque TUSER é um sinal AXI de entrada,
não um campo armazenado no PCAP clássico.
"""
from __future__ import annotations

import argparse
import json
import struct
from dataclasses import asdict, dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_PCAP = ROOT / "sim" / "trafego_referencia_P01_P14.pcap"
DEFAULT_JSON = ROOT / "sim" / "trafego_referencia_esperado.json"


def checksum16(data: bytes) -> int:
    if len(data) & 1:
        data += b"\x00"
    total = sum(int.from_bytes(data[i:i + 2], "big") for i in range(0, len(data), 2))
    while total >> 16:
        total = (total & 0xFFFF) + (total >> 16)
    return (~total) & 0xFFFF


def ipv4_bytes(ip: str) -> bytes:
    return bytes(int(x) for x in ip.split("."))


def build_ipv4(
    src_ip: str,
    dst_ip: str,
    protocol: int,
    payload: bytes,
    identification: int,
    ihl: int = 5,
    fragment_field: int = 0,
) -> bytes:
    if not 5 <= ihl <= 15:
        raise ValueError("IHL do construtor deve estar entre 5 e 15")
    options = bytes((0x01,)) * (4 * (ihl - 5))
    total_length = 20 + len(options) + len(payload)
    header0 = struct.pack(
        "!BBHHHBBH4s4s",
        (4 << 4) | ihl,
        0,
        total_length,
        identification,
        fragment_field,
        64,
        protocol,
        0,
        ipv4_bytes(src_ip),
        ipv4_bytes(dst_ip),
    ) + options
    csum = checksum16(header0)
    header = struct.pack(
        "!BBHHHBBH4s4s",
        (4 << 4) | ihl,
        0,
        total_length,
        identification,
        fragment_field,
        64,
        protocol,
        csum,
        ipv4_bytes(src_ip),
        ipv4_bytes(dst_ip),
    ) + options
    return header + payload


def build_tcp(src_ip: str, dst_ip: str, src_port: int, dst_port: int, payload: bytes = b"") -> bytes:
    tcp0 = struct.pack("!HHIIBBHHH", src_port, dst_port, 100, 0, 5 << 4, 0x18, 65535, 0, 0) + payload
    pseudo = ipv4_bytes(src_ip) + ipv4_bytes(dst_ip) + bytes((0, 6)) + struct.pack("!H", len(tcp0))
    csum = checksum16(pseudo + tcp0)
    return struct.pack("!HHIIBBHHH", src_port, dst_port, 100, 0, 5 << 4, 0x18, 65535, csum, 0) + payload


def build_udp(src_ip: str, dst_ip: str, src_port: int, dst_port: int, payload: bytes = b"") -> bytes:
    length = 8 + len(payload)
    udp0 = struct.pack("!HHHH", src_port, dst_port, length, 0) + payload
    pseudo = ipv4_bytes(src_ip) + ipv4_bytes(dst_ip) + bytes((0, 17)) + struct.pack("!H", length)
    csum = checksum16(pseudo + udp0) or 0xFFFF
    return struct.pack("!HHHH", src_port, dst_port, length, csum) + payload


def ethernet(ip_packet: bytes, ethertype: int = 0x0800) -> bytes:
    dst = bytes.fromhex("020000000002")
    src = bytes.fromhex("020000000001")
    return dst + src + struct.pack("!H", ethertype) + ip_packet


@dataclass
class PacketCase:
    packet_id: str
    frame: bytes
    timestamp_ns: int
    expected_valid: bool
    tuser: int = 1
    scenario: str = ""
    original_length: int | None = None


def make_cases() -> list[PacketCase]:
    f1_src, f1_dst = "192.168.1.10", "8.8.8.8"
    f2_src, f2_dst = "192.168.1.20", "8.8.4.4"
    f3_src, f3_dst = "10.0.0.1", "10.0.0.2"
    f4_src, f4_dst = "172.16.0.10", "172.16.0.20"

    p01 = ethernet(build_ipv4(f1_src, f1_dst, 6, build_tcp(f1_src, f1_dst, 52100, 443), 1))
    p02 = ethernet(build_ipv4(f1_src, f1_dst, 6, build_tcp(f1_src, f1_dst, 52100, 443, bytes.fromhex("0102030405060708090a0b0c0d0e0f1011121314")), 2))
    p03 = ethernet(build_ipv4(f1_src, f1_dst, 6, build_tcp(f1_src, f1_dst, 52100, 443, bytes.fromhex("aabbccddeeff001122334455")), 3))
    p04 = ethernet(build_ipv4(f2_src, f2_dst, 17, build_udp(f2_src, f2_dst, 40000, 53), 4))
    p05 = ethernet(build_ipv4(f2_src, f2_dst, 17, build_udp(f2_src, f2_dst, 40000, 53, bytes.fromhex("1122334455667788")), 5))
    p06 = ethernet(build_ipv4(f3_src, f3_dst, 6, build_tcp(f3_src, f3_dst, 12345, 80), 6, ihl=6))
    p07 = ethernet(build_ipv4(f3_src, f3_dst, 6, build_tcp(f3_src, f3_dst, 12345, 80), 7, ihl=15))
    p08 = ethernet(build_ipv4(f4_src, f4_dst, 17, build_udp(f4_src, f4_dst, 5000, 5001), 8))

    # P09: IPv4/ICMP (protocolo 1), fora do conjunto TCP/UDP.
    p09 = ethernet(build_ipv4("192.0.2.1", "192.0.2.2", 1, bytes.fromhex("0800000000000000"), 9))
    # P10: EtherType IPv6, nao IPv4.
    p10 = ethernet(bytes.fromhex("6000000000083b40") + bytes(40), ethertype=0x86DD)
    # P11: IPv4 com MF=1 (fragmentado).
    p11 = ethernet(build_ipv4("198.51.100.1", "198.51.100.2", 6,
                              build_tcp("198.51.100.1", "198.51.100.2", 1000, 80),
                              11, fragment_field=0x2000))
    # P12: quadro TCP bem formado, mas o testbench aplicara TUSER=0 no TLAST.
    p12 = ethernet(build_ipv4(f1_src, f1_dst, 6, build_tcp(f1_src, f1_dst, 52100, 443), 12))
    # P13: nibble IHL=4 (malformado). O cabeçalho foi montado manualmente.
    malformed_ip = bytearray(build_ipv4("203.0.113.1", "203.0.113.2", 6,
                                         build_tcp("203.0.113.1", "203.0.113.2", 1234, 80),
                                         13))
    malformed_ip[0] = 0x44
    malformed_ip[2:4] = struct.pack("!H", 40)
    malformed_ip[10:12] = b"\x00\x00"
    malformed_ip[10:12] = struct.pack("!H", checksum16(bytes(malformed_ip[:20])))
    p13 = ethernet(bytes(malformed_ip))
    # P14: quadro truncado antes da chegada dos campos de transporte.
    p14_full = ethernet(build_ipv4("203.0.113.10", "203.0.113.20", 6,
                                   build_tcp("203.0.113.10", "203.0.113.20", 2222, 443), 14))
    p14 = p14_full[:32]

    return [
        PacketCase("P01", p01, 1_000_000_000, True, scenario="TCP F1, início"),
        PacketCase("P02", p02, 1_000_100_000, True, scenario="TCP F1, segundo pacote"),
        PacketCase("P03", p03, 1_000_500_000, True, scenario="TCP F1, terceiro pacote"),
        PacketCase("P04", p04, 2_000_000_000, True, scenario="UDP F2, início"),
        PacketCase("P05", p05, 2_000_200_000, True, scenario="UDP F2, segundo pacote"),
        PacketCase("P06", p06, 3_000_000_000, True, scenario="TCP F3, IHL=6"),
        PacketCase("P07", p07, 3_000_900_000, True, scenario="TCP F3, IHL=15"),
        PacketCase("P08", p08, 4_000_000_000, True, scenario="UDP F4, pacote único"),
        PacketCase("P09", p09, 5_000_000_000, False, scenario="Protocolo IPv4 não suportado"),
        PacketCase("P10", p10, 5_100_000_000, False, scenario="EtherType não IPv4"),
        PacketCase("P11", p11, 5_200_000_000, False, scenario="IPv4 fragmentado (MF=1)"),
        PacketCase("P12", p12, 5_300_000_000, False, tuser=0, scenario="TUSER=0 no TLAST"),
        PacketCase("P13", p13, 5_400_000_000, False, scenario="IHL=4 inválido"),
        PacketCase("P14", p14, 5_500_000_000, False, scenario="TLAST antecipado / quadro truncado", original_length=len(p14_full)),
    ]


def write_pcap(path: Path, cases: list[PacketCase]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as f:
        # PCAP clássico little-endian, timestamps em microssegundos, DLT_EN10MB=1.
        f.write(struct.pack("<IHHIIII", 0xA1B2C3D4, 2, 4, 0, 0, 65535, 1))
        for case in cases:
            sec, rem_ns = divmod(case.timestamp_ns, 1_000_000_000)
            usec, ns_remainder = divmod(rem_ns, 1_000)
            if ns_remainder:
                raise ValueError(f"{case.packet_id}: PCAP usec nao representa {case.timestamp_ns} ns exatamente")
            original_length = case.original_length if case.original_length is not None else len(case.frame)
            f.write(struct.pack("<IIII", sec, usec, len(case.frame), original_length))
            f.write(case.frame)


def parse_reference(frame: bytes, timestamp_ns: int, tuser: int) -> dict | None:
    """Modelo funcional independente do RTL, restrito ao contrato atual."""
    if tuser != 1 or len(frame) < 14 or frame[12:14] != b"\x08\x00":
        return None
    if len(frame) < 34:
        return None
    first = frame[14]
    version, ihl = first >> 4, first & 0xF
    if version != 4 or ihl < 5:
        return None
    ip_header_bytes = ihl * 4
    if len(frame) < 14 + ip_header_bytes or len(frame) < 24:
        return None
    total_length = int.from_bytes(frame[16:18], "big")
    if total_length < ip_header_bytes + 4 or len(frame) < 14 + total_length:
        return None
    fragment = int.from_bytes(frame[20:22], "big")
    if fragment & 0x3FFF:  # MF ou Fragment Offset != 0 (DF nao causa descarte)
        return None
    proto = frame[23]
    if proto not in (6, 17):
        return None
    transport_offset = 14 + ip_header_bytes
    if len(frame) < transport_offset + 4:
        return None
    return {
        "src_ip": frame[26:30].hex(),
        "dst_ip": frame[30:34].hex(),
        "src_port": int.from_bytes(frame[transport_offset:transport_offset + 2], "big"),
        "dst_port": int.from_bytes(frame[transport_offset + 2:transport_offset + 4], "big"),
        "protocol": proto,
        "packet_length": total_length,
        "timestamp_ns": timestamp_ns,
    }


def crc16_ccitt_false(data: bytes) -> int:
    crc = 0xFFFF
    for value in data:
        crc ^= value << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) & 0xFFFF if (crc & 0x8000) else (crc << 1) & 0xFFFF
    return crc


def aggregate_features(cases: list[PacketCase]) -> dict:
    table: dict[int, dict] = {}
    counts = {"MISS": 0, "HIT": 0, "COLLISION": 0}
    accepted = []
    dropped = []
    for case in cases:
        metadata = parse_reference(case.frame, case.timestamp_ns, case.tuser)
        if metadata is None:
            dropped.append(case.packet_id)
            continue
        accepted.append(case.packet_id)
        key_bytes = (bytes.fromhex(metadata["src_ip"]) + bytes.fromhex(metadata["dst_ip"])
                     + struct.pack("!HHB", metadata["src_port"], metadata["dst_port"], metadata["protocol"]))
        index = crc16_ccitt_false(key_bytes)
        key_int = int.from_bytes(key_bytes, "big")
        existing = table.get(index)
        if existing is None:
            table[index] = {
                "hash_index": index,
                "flow_key": key_int,
                "packet_count": 1,
                "byte_count": metadata["packet_length"],
                "first_timestamp": metadata["timestamp_ns"],
                "last_timestamp": metadata["timestamp_ns"],
            }
            counts["MISS"] += 1
        elif existing["flow_key"] == key_int:
            existing["packet_count"] += 1
            existing["byte_count"] += metadata["packet_length"]
            existing["last_timestamp"] = metadata["timestamp_ns"]
            counts["HIT"] += 1
        else:
            counts["COLLISION"] += 1
    flows = []
    for entry in sorted(table.values(), key=lambda e: e["hash_index"]):
        duration = entry["last_timestamp"] - entry["first_timestamp"]
        feature_vector = (entry["flow_key"] << 144) | (entry["packet_count"] << 112) | (entry["byte_count"] << 80) | duration
        flows.append({**entry, "duration": duration, "feature_vector_hex": f"{feature_vector:062x}"})
    return {
        "accepted_packets": accepted,
        "dropped_packets": dropped,
        "classification_counts": counts,
        "flows": flows,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pcap", type=Path, default=DEFAULT_PCAP)
    parser.add_argument("--json", type=Path, default=DEFAULT_JSON)
    args = parser.parse_args()
    cases = make_cases()
    write_pcap(args.pcap, cases)
    expected = aggregate_features(cases)
    args.json.parent.mkdir(parents=True, exist_ok=True)
    args.json.write_text(json.dumps({
        "pcap": args.pcap.name,
        "format": "PCAP classic little-endian, Ethernet II, microsecond timestamps",
        "timestamp_contract": "80-bit unsigned scalar nanoseconds",
        "packet_cases": [{
            "packet_id": c.packet_id,
            "frame_bytes": len(c.frame),
            "timestamp_ns": c.timestamp_ns,
            "expected_valid": c.expected_valid,
            "tuser_on_tlast": c.tuser,
            "scenario": c.scenario,
        } for c in cases],
        "feature_reference": expected,
    }, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"PCAP criado: {args.pcap}")
    print(f"Registros: {len(cases)}; válidos esperados: 8; descartados esperados: 6")
    print(f"Bytes: {[len(c.frame) for c in cases]}")
    print(f"Features: {len(expected['flows'])}; classificacao: {expected['classification_counts']}")
    print(f"JSON de referência: {args.json}")


if __name__ == "__main__":
    main()
