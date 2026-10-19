#!/usr/bin/env python3
"""Release metadata: validate artifacts, merge a verified build report, render docs."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RELEASE = ROOT / 'release'
PRODUCTS = ('cooloo', 'cooloo-text', 'cooloo-cli', 'cooloo-workbench')


def filename(product, platform):
    return product + ('-darwin-arm64' if platform == 'darwin' else '-windows-x86_64.exe')


EXPECTED = {filename(p, s): (p, s, 'arm64' if s == 'darwin' else 'x86_64')
            for p in PRODUCTS for s in ('darwin', 'windows')}


def digest(path):
    with path.open('rb') as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()


def load(directory=RELEASE):
    manifest = json.loads((directory / 'manifest.json').read_text())
    if manifest.get('schema_version') != 1:
        raise ValueError('unsupported release manifest schema')
    return manifest


def check_entry(entry, directory):
    name = entry['filename']
    if name not in EXPECTED or tuple(entry[k] for k in ('product', 'os', 'arch')) != EXPECTED[name]:
        raise ValueError(f'invalid artifact identity: {name}')
    path = directory / name
    if not path.is_file() or path.is_symlink():
        raise ValueError(f'missing/linked artifact: {name}')
    with path.open('rb') as f:
        header = f.read(128)
    if header.startswith(b'version https://git-lfs.github.com/spec/v1'):
        raise ValueError(f'LFS pointer instead of binary: {name}')
    magic = b'MZ' if entry['os'] == 'windows' else b'\xcf\xfa\xed\xfe'
    if not header.startswith(magic):
        raise ValueError(f'wrong executable format: {name}')
    if path.stat().st_size != entry['bytes'] or digest(path) != entry['sha256']:
        raise ValueError(f'size/SHA-256 mismatch: {name}')


def sums(manifest):
    return ''.join(f"{e['sha256']}  {e['filename']}\n" for e in manifest['artifacts'])


def validate(manifest, directory=RELEASE, check_sums=True):
    names = [e['filename'] for e in manifest['artifacts']]
    if len(names) != len(EXPECTED) or set(names) != set(EXPECTED):
        raise ValueError('manifest must contain exactly the eight unique products/platforms')
    for entry in manifest['artifacts']:
        check_entry(entry, directory)
    if check_sums and (directory / 'SHA256SUMS').read_text() != sums(manifest):
        raise ValueError('SHA256SUMS is not generated from manifest.json')


def merge(manifest, report, directory):
    if report.get('schema_version') != 1 or report.get('status') != 'passed':
        raise ValueError('only successful schema-1 build reports can be installed')
    entries = report['artifacts']
    names = [e['filename'] for e in entries]
    if not names or len(names) != len(set(names)):
        raise ValueError('empty/duplicate build artifacts')
    for entry in entries:
        check_entry(entry, directory)
        for key in ('source_commit', 'source_archive_sha256', 'test_server_commit',
                    'build_date', 'build_platform', 'verification', 'source_dirty'):
            if key not in entry:
                raise ValueError(f'missing provenance: {key}')
        if entry['source_dirty'] is not False:
            raise ValueError('release requires committed source')
    updates = {e['filename']: e for e in entries}
    result = dict(manifest, status='development-artifacts', updated=report['build_date'],
                  artifacts=[updates.get(e['filename'], e) for e in manifest['artifacts']])
    versions = {e.get('client_version', manifest['client_version']) for e in result['artifacts']}
    result['client_version'] = versions.pop() if len(versions) == 1 else 'mixed'
    validate(result, directory, check_sums=False)
    return result


def readme(manifest):
    lines = [f"# cooloo client {manifest['client_version']} artifacts", '',
             'Generated from `manifest.json`; edit the build inputs/report, not this file.', '',
             'Four products for macOS arm64 and Windows x86_64. Binaries are unsigned,',
             'not notarized, and tracked by Git LFS. No Linux GUI artifact is published.', '',
             '- `cooloo`: communication CLI + GUI workbench.',
             '- `cooloo-text`: standalone text editor.',
             '- `cooloo-cli`: headless communication CLI.',
             '- `cooloo-workbench`: headless projection/validation and Lua runner.', '',
             '## Provenance', '',
             '| File | Source commit | Build date | Bytes |',
             '|---|---|---|---|']
    for e in manifest['artifacts']:
        lines.append(f"| `{e['filename']}` | `{e['source_commit']}` | {e['build_date']} | {e['bytes']} |")
    sources = {e['source_commit'] for e in manifest['artifacts']}
    lines += ['', ('Mixed source revisions: each artifact retains its own provenance.' if len(sources) > 1
                  else 'All artifacts use the same source revision.'), '',
              'SHA-256 values and toolchain details are in `manifest.json`; `SHA256SUMS`',
              'is derived from it. This development refresh does not create a tag,',
              'GitHub Release or Python publication.', '', '## Verification', '']
    groups = {}
    for e in manifest['artifacts']:
        groups.setdefault(e['verification'], []).append(e['filename'])
    for verification, names in groups.items():
        lines += ['- ' + ', '.join(f'`{n}`' for n in names) + ': ' + verification, '']
    lines += ['Validate with `python3 tools/release_manifest.py`.', '']
    return '\n'.join(lines)


def release_notes(manifest):
    print(f"## cooloo client {manifest['client_version']} ({manifest['status']})\n")
    print('| Product | OS | Architecture | File | SHA-256 |')
    print('|---|---|---|---|---|')
    for e in manifest['artifacts']:
        print(f"| {e['product']} | {e['os']} | {e['arch']} | `{e['filename']}` | `{e['sha256']}` |")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, default=RELEASE)
    parser.add_argument('--merge-report', type=Path, help='merge verified report into staged artifacts')
    parser.add_argument('--release-notes', action='store_true')
    args = parser.parse_args()
    manifest = load(args.directory)
    if args.merge_report:
        manifest = merge(manifest, json.loads(args.merge_report.read_text()), args.directory)
        (args.directory / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        (args.directory / 'SHA256SUMS').write_text(sums(manifest))
        (args.directory / 'README.md').write_text(readme(manifest))
    validate(manifest, args.directory)
    if args.release_notes:
        release_notes(manifest)
    else:
        print(f"validated {len(manifest['artifacts'])} artifacts")


if __name__ == '__main__':
    main()
