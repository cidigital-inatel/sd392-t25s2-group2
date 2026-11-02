#!/usr/bin/env python3
"""Modelo de referência independente PCAP -> Parser -> Flow Table -> Features.

Suporta PCAP clássico Ethernet II (DLT_EN10MB). Timestamp de saída: inteiro
absoluto em nanossegundos de 80 bits. No tráfego P01-P14, P12 recebe TUSER=0
por convenção de teste porque o PCAP clássico não transporta esse sideband.
"""
from __future__ import annotations

import argparse
import csv
import json
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_PCAP = ROOT / "sim" / "trafego_referencia_P01_P14.pcap"
DEFAULT_JSON = ROOT / "sim" / "modelo_referencia_features.json"
DEFAULT_MEM = ROOT / "sim" / "feature_vectors_esperados.mem"
DEFAULT_CSV = ROOT / "sim" / "metadados_esperados.csv"
TUSER_OVERRIDES = {12: 0}


def read_classic_pcap(path: Path) -> list[tuple[bytes, int]]:
    raw = path.read_bytes()
    if len(raw) < 24:
        raise ValueError("PCAP menor que o cabecalho global")
    magic = raw[:4]
    if magic == bytes.fromhex("d4c3b2a1"):
        endian, scale = "<", 1_000
    elif magic == bytes.fromhex("a1b2c3d4"):
        endian, scale = ">", 1_000
    elif magic == bytes.fromhex("4d3cb2a1"):
        endian, scale = "<", 1
    elif magic == bytes.fromhex("a1b23c4d"):
        endian, scale = ">", 1
    else:
        raise ValueError(f"Magic PCAP nao suportado: {magic.hex()}")
    major, minor, _thiszone, _sigfigs, snaplen, network = struct.unpack(endian + "HHIIII", raw[4:24])
    if (major, minor) != (2, 4):
        raise ValueError(f"Versao PCAP nao suportada: {major}.{minor}")
    if network != 1:
        raise ValueError(f"Esperado DLT_EN10MB=1, recebido {network}")
    if snaplen == 0:
        raise ValueError("snaplen invalido")
    offset = 24
    packets: list[tuple[bytes, int]] = []
    while offset < len(raw):
        if offset + 16 > len(raw):
            raise ValueError("Cabecalho de registro PCAP truncado")
        sec, frac, incl_len, orig_len = struct.unpack(endian + "IIII", raw[offset:offset + 16])
        offset += 16
        if incl_len > snaplen or incl_len > orig_len:
            raise ValueError(f"Comprimento de registro inconsistente: incl={incl_len}, orig={orig_len}, snaplen={snaplen}")
        if offset + incl_len > len(raw):
            raise ValueError("Payload de registro PCAP truncado")
        frame = raw[offset:offset + incl_len]
        offset += incl_len
        timestamp_ns = sec * 1_000_000_000 + frac * scale
        packets.append((frame, timestamp_ns))
    return packets


def parse_frame(frame: bytes, timestamp_ns: int, tuser: int) -> dict | None:
    if tuser != 1 or len(frame) < 14 or frame[12:14] != b"\x08\x00":
        return None
    if len(frame) < 34:
        return None
    first = frame[14]
    version, ihl = first >> 4, first & 0x0F
    if version != 4 or ihl < 5:
        return None
    ip_header_len = 4 * ihl
    if len(frame) < 14 + ip_header_len:
        return None
    total_len = int.from_bytes(frame[16:18], "big")
    if total_len < ip_header_len + 4 or len(frame) < 14 + total_len:
        return None
    fragment_field = int.from_bytes(frame[20:22], "big")
    if fragment_field & 0x3FFF:  # MF=1 ou Fragment Offset diferente de zero
        return None
    proto = frame[23]
    if proto not in (6, 17):
        return None
    transport_offset = 14 + ip_header_len
    if len(frame) < transport_offset + 4:
        return None
    return {
        "src_ip": frame[26:30].hex(),
        "dst_ip": frame[30:34].hex(),
        "src_port": int.from_bytes(frame[transport_offset:transport_offset + 2], "big"),
        "dst_port": int.from_bytes(frame[transport_offset + 2:transport_offset + 4], "big"),
        "protocol": proto,
        "packet_length": total_len,
        "timestamp_ns": timestamp_ns,
    }


def crc16_ccitt_false(data: bytes) -> int:
    crc = 0xFFFF
    for value in data:
        crc ^= value << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) & 0xFFFF if crc & 0x8000 else (crc << 1) & 0xFFFF
    return crc


def model(packets: list[tuple[bytes, int]]) -> tuple[list[dict], list[dict], dict]:
    table: dict[int, dict] = {}
    packet_log: list[dict] = []
    dropped: list[dict] = []
    result_counts = {"MISS": 0, "HIT": 0, "COLLISION": 0}
    for packet_index, (frame, timestamp_ns) in enumerate(packets, start=1):
        tuser = TUSER_OVERRIDES.get(packet_index, 1)
        meta = parse_frame(frame, timestamp_ns, tuser)
        if meta is None:
            dropped.append({"packet": packet_index, "tuser": tuser, "frame_bytes": len(frame)})
            packet_log.append({"packet": packet_index, "classification": "DROP"})
            continue
        key = bytes.fromhex(meta["src_ip"] + meta["dst_ip"]) + struct.pack(
            "!HHB", meta["src_port"], meta["dst_port"], meta["protocol"]
        )
        key_int = int.from_bytes(key, "big")
        index = crc16_ccitt_false(key)
        current = table.get(index)
        if current is None:
            table[index] = {
                "hash_index": index,
                "flow_key": key_int,
                "src_ip": meta["src_ip"],
                "dst_ip": meta["dst_ip"],
                "src_port": meta["src_port"],
                "dst_port": meta["dst_port"],
                "protocol": meta["protocol"],
                "packet_count": 1,
                "byte_count": meta["packet_length"],
                "first_timestamp": timestamp_ns,
                "last_timestamp": timestamp_ns,
            }
            classification = "MISS"
        elif current["flow_key"] == key_int:
            current["packet_count"] += 1
            current["byte_count"] += meta["packet_length"]
            current["last_timestamp"] = timestamp_ns
            classification = "HIT"
        else:
            classification = "COLLISION"
        result_counts[classification] += 1
        packet_log.append({
            "packet": packet_index,
            "classification": classification,
            "hash_index": index,
            "flow_key_hex": f"{key_int:026x}",
            **meta,
        })

    features = []
    for entry in sorted(table.values(), key=lambda item: item["hash_index"]):
        duration = entry["last_timestamp"] - entry["first_timestamp"]
        vector = ((entry["flow_key"] << 144) |
                  (entry["packet_count"] << 112) |
                  (entry["byte_count"] << 80) |
                  duration)
        features.append({
            **entry,
            "duration": duration,
            "feature_vector_hex": f"{vector:062x}",
        })
    summary = {
        "packet_records": len(packets),
        "valid_metadata_packets": sum(1 for x in packet_log if x["classification"] != "DROP"),
        "dropped_packets": len(dropped),
        "classification_counts": result_counts,
        "features": len(features),
        "dropped": dropped,
    }
    return packet_log, features, summary


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--pcap", type=Path, default=DEFAULT_PCAP)
    ap.add_argument("--json", type=Path, default=DEFAULT_JSON)
    ap.add_argument("--mem", type=Path, default=DEFAULT_MEM)
    ap.add_argument("--csv", type=Path, default=DEFAULT_CSV)
    args = ap.parse_args()

    packets = read_classic_pcap(args.pcap)
    packet_log, features, summary = model(packets)
    args.json.parent.mkdir(parents=True, exist_ok=True)
    args.json.write_text(json.dumps({
        "pcap": args.pcap.name,
        "contract": {
            "flow_direction": "unidirectional",
            "flow_key": "src_ip || dst_ip || src_port || dst_port || protocol",
            "packet_length": "IPv4 Total Length",
            "byte_count": "sum of IPv4 Total Length",
            "timestamp": "unsigned 80-bit scalar nanoseconds",
            "hash": "CRC-16/CCITT-FALSE, poly=0x1021, init=0xFFFF, no reflection, xorout=0",
            "collision_policy": "discard new packet; do not overwrite existing hash slot",
        },
        "summary": summary,
        "packet_results": packet_log,
        "features": features,
    }, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    args.mem.parent.mkdir(parents=True, exist_ok=True)
    args.mem.write_text("\n".join(x["feature_vector_hex"] for x in features) + "\n", encoding="ascii")
    with args.csv.open("w", newline="", encoding="utf-8") as f:
        fields = ["packet", "classification", "hash_index", "flow_key_hex", "src_ip", "dst_ip",
                  "src_port", "dst_port", "protocol", "packet_length", "timestamp_ns"]
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        for row in packet_log:
            writer.writerow({field: row.get(field, "") for field in fields})

    print(f"PCAP lido: {args.pcap}")
    print(f"Registros={summary['packet_records']} | metadados={summary['valid_metadata_packets']} | descartados={summary['dropped_packets']}")
    print(f"MISS={summary['classification_counts']['MISS']} HIT={summary['classification_counts']['HIT']} COLLISION={summary['classification_counts']['COLLISION']}")
    print(f"Features={summary['features']}")
    for feature in features:
        print(f"index={feature['hash_index']:5d} count={feature['packet_count']} bytes={feature['byte_count']} duration={feature['duration']} ns")
    print(f"JSON: {args.json}\nMEM: {args.mem}\nCSV: {args.csv}")


if __name__ == "__main__":
    main()
