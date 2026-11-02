#!/usr/bin/env python3
"""Confere de forma independente o par dirigido de colisao usado no XSim."""
from __future__ import annotations
import json
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "sim" / "referencia_colisao.json"

A = {
    "src_ip": "10.1.26.137", "dst_ip": "192.0.2.1",
    "src_port": 2248, "dst_port": 443, "protocol": 6,
    "packet_length": 40, "timestamp_ns": 1_000_000_000,
}
B = {
    "src_ip": "10.1.59.180", "dst_ip": "192.0.2.1",
    "src_port": 22004, "dst_port": 443, "protocol": 6,
    "packet_length": 60, "timestamp_ns": 1_000_100_000,
}


def flow_key(packet: dict) -> bytes:
    return (bytes(map(int, packet["src_ip"].split(".")))
            + bytes(map(int, packet["dst_ip"].split(".")))
            + struct.pack("!HHB", packet["src_port"], packet["dst_port"], packet["protocol"]))


def crc16_ccitt_false(data: bytes) -> int:
    crc = 0xFFFF
    for value in data:
        crc ^= value << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) & 0xFFFF if crc & 0x8000 else (crc << 1) & 0xFFFF
    return crc


def main() -> None:
    key_a, key_b = flow_key(A), flow_key(B)
    hash_a, hash_b = crc16_ccitt_false(key_a), crc16_ccitt_false(key_b)
    assert key_a != key_b, "As chaves precisam ser diferentes"
    assert hash_a == hash_b == 0x58BC, f"Colisao esperada em 0x58BC, obtido {hash_a:04X}/{hash_b:04X}"

    vector = ((int.from_bytes(key_a, "big") << 144)
              | (1 << 112) | (A["packet_length"] << 80))
    report = {
        "purpose": "Directed CRC16 collision test for the Flow Table policy",
        "hash_index": f"0x{hash_a:04X}",
        "packet_a": {**A, "flow_key_hex": key_a.hex(), "classification": "MISS"},
        "packet_b": {**B, "flow_key_hex": key_b.hex(), "classification": "COLLISION"},
        "expected_collision_count": 1,
        "expected_table_policy": "Preserve packet A entry; discard packet B; do not increment bytes or packet count",
        "expected_exported_features": 1,
        "expected_feature_vector_hex": f"{vector:062x}",
    }
    OUT.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print("PASS: duas flow_keys diferentes possuem o mesmo CRC16.")
    print(f"hash_index A/B: 0x{hash_a:04X} / 0x{hash_b:04X}")
    print(f"flow_key A: {key_a.hex()}")
    print(f"flow_key B: {key_b.hex()}")
    print("classificacao esperada: MISS / COLLISION")
    print(f"feature esperada (somente A): {vector:062x}")
    print(f"JSON: {OUT}")


if __name__ == "__main__":
    main()
