#!/usr/bin/env python3
"""Validate release artifacts and render derived release metadata."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RELEASE = ROOT / "release"


def load():
    manifest = json.loads((RELEASE / "manifest.json").read_text())
    if manifest.get("schema_version") != 1:
        raise ValueError("unsupported release manifest schema")
    return manifest


def validate(manifest):
    lines = []
    for entry in manifest["artifacts"]:
        path = RELEASE / entry["filename"]
        if not path.is_file():
            raise ValueError(f"missing artifact: {entry['filename']}")
        if path.stat().st_size != entry["bytes"]:
            raise ValueError(f"size mismatch: {entry['filename']}")
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if digest != entry["sha256"]:
            raise ValueError(f"SHA-256 mismatch: {entry['filename']}")
        lines.append(f"{digest}  {entry['filename']}")
    if (RELEASE / "SHA256SUMS").read_text().splitlines() != lines:
        raise ValueError("SHA256SUMS is not generated from manifest.json")


def release_notes(manifest):
    print(f"## cooloo client {manifest['client_version']} ({manifest['status']})")
    print()
    print("Artifact checksums and provenance are recorded in `manifest.json`.")
    print()
    print("| Product | OS | Architecture | File | SHA-256 |")
    print("|---|---|---|---|---|")
    for entry in manifest["artifacts"]:
        print(f"| {entry['product']} | {entry['os']} | {entry['arch']} | "
              f"`{entry['filename']}` | `{entry['sha256']}` |")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--release-notes", action="store_true",
                        help="render Markdown suitable for a GitHub Release")
    args = parser.parse_args()
    manifest = load()
    validate(manifest)
    if args.release_notes:
        release_notes(manifest)
    else:
        print(f"validated {len(manifest['artifacts'])} artifacts")


if __name__ == "__main__":
    main()
