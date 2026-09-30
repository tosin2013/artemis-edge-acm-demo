#!/usr/bin/env python3
"""Validate a GCP service-account JSON key file.

Exit 0 if the key is structurally valid (JSON parses, private_key is
PKCS#8 PEM, every base64 body line is 64 chars except the last, and
the cryptography library can load the key).

Exit 1 with a human-readable diagnostic on any failure.  The PEM body
is never printed — only line numbers and lengths.

Usage:
    python3 scripts/validate-gcp-key.py KEY.json
    python3 scripts/validate-gcp-key.py --help
"""

from __future__ import annotations

import argparse
import base64
import json
import sys
from pathlib import Path


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Validate a GCP service-account JSON key file.",
        epilog="Exits 0 on a valid key, 1 on structural damage.",
    )
    parser.add_argument(
        "keyfile",
        type=Path,
        help="Path to the GCP service-account JSON key file",
    )
    return parser.parse_args()


def _fail(msg: str) -> None:
    print(f"FAIL: {msg}", file=sys.stderr)
    sys.exit(1)


def main() -> None:
    args = _parse_args()

    # --- 1. JSON parses ---------------------------------------------------
    try:
        data = json.loads(args.keyfile.read_text(encoding="utf-8"))
    except FileNotFoundError:
        _fail(f"File not found: {args.keyfile}")
    except json.JSONDecodeError as exc:
        _fail(f"Invalid JSON: {exc}")

    if not isinstance(data, dict):
        _fail("JSON top-level value is not an object.")

    # --- 2. private_key field exists and is a string ----------------------
    pem_str = data.get("private_key")
    if not pem_str or not isinstance(pem_str, str):
        _fail("Missing or non-string 'private_key' field.")

    # --- 3. PEM envelope: PKCS#8 -----------------------------------------
    lines = pem_str.strip().splitlines()
    if not lines:
        _fail("private_key is empty after stripping whitespace.")

    expected_header = "-----BEGIN PRIVATE KEY-----"
    expected_footer = "-----END PRIVATE KEY-----"
    if lines[0].strip() != expected_header:
        _fail(
            f"PEM header mismatch. Expected '{expected_header}', "
            f"got '{lines[0].strip()}'."
        )
    if lines[-1].strip() != expected_footer:
        _fail(
            f"PEM footer mismatch. Expected '{expected_footer}', "
            f"got '{lines[-1].strip()}'."
        )

    body_lines = [l.strip() for l in lines[1:-1] if l.strip()]
    if not body_lines:
        _fail("PEM body is empty (no base64 lines between header and footer).")

    # --- 4. Line-length check: 64 chars except last ----------------------
    bad_lines: list[tuple[int, int]] = []
    for idx, line in enumerate(body_lines):
        line_num = idx + 2  # 1-indexed, offset by header line
        if idx < len(body_lines) - 1:
            if len(line) != 64:
                bad_lines.append((line_num, len(line)))
        else:
            if len(line) > 64:
                bad_lines.append((line_num, len(line)))

    if bad_lines:
        report = "; ".join(
            f"line {n}: {length} chars" for n, length in bad_lines
        )
        _fail(
            f"PEM body line-length violation (expected 64 chars per middle "
            f"line, ≤64 for last). {report}"
        )

    # --- 5. Concatenated base64 length % 4 == 0 --------------------------
    b64_concat = "".join(body_lines)
    if len(b64_concat) % 4 != 0:
        _fail(
            f"Concatenated base64 length is {len(b64_concat)}, which is not "
            f"a multiple of 4. Possible truncation or rewrap damage."
        )

    # --- 6. base64 decodes ------------------------------------------------
    try:
        base64.b64decode(b64_concat, validate=True)
    except Exception as exc:
        _fail(f"base64 decode failed: {exc}")

    # --- 7. cryptography can load the PEM ---------------------------------
    try:
        from cryptography.hazmat.primitives.serialization import (
            load_pem_private_key,
        )
    except ImportError:
        _fail(
            "Python 'cryptography' package is not installed. "
            "Cannot verify the key is loadable."
        )

    pem_bytes = pem_str.encode("utf-8")
    try:
        load_pem_private_key(pem_bytes, password=None)
    except Exception as exc:
        _fail(f"cryptography could not load the PEM private key: {exc}")

    # --- All checks passed ------------------------------------------------
    print(f"OK: {args.keyfile} is a valid GCP service-account key.")
    sys.exit(0)


if __name__ == "__main__":
    main()
