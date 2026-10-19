#!/usr/bin/env python3
"""Offline regression checks for metadata merge and release trust boundaries."""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('release_manifest', Path(__file__).resolve().parents[1] / 'tools/release_manifest.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class MetadataTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.manifest = dict(schema_version=1, client_version='0.3.0', status='development-artifacts', artifacts=[])
        for name, (product, platform, arch) in m.EXPECTED.items():
            path = self.root / name
            path.write_bytes((b'MZ' if platform == 'windows' else b'\xcf\xfa\xed\xfe') + b'fixture')
            self.manifest['artifacts'].append(dict(filename=name, product=product, os=platform, arch=arch,
                bytes=path.stat().st_size, sha256=m.digest(path), source_commit='a'*40,
                source_archive_sha256='b'*64, source_dirty=False, test_server_commit='c'*40,
                build_date='2026-10-19', build_platform='fixture', verification='fixture'))
        (self.root / 'SHA256SUMS').write_text(m.sums(self.manifest))

    def report(self):
        e = copy.deepcopy(self.manifest['artifacts'][0])
        e['source_commit'] = 'd'*40
        return dict(schema_version=1, status='passed', build_date='2026-10-20', artifacts=[e])

    def test_partial_merge_preserves_other_provenance(self):
        result = m.merge(self.manifest, self.report(), self.root)
        self.assertEqual(result['artifacts'][1:], self.manifest['artifacts'][1:])
        self.assertEqual(result['artifacts'][0]['source_commit'], 'd'*40)
        self.assertIn('Mixed source revisions', m.readme(result))

    def test_corrupt_artifact_rejected(self):
        (self.root / self.manifest['artifacts'][0]['filename']).write_bytes(b'corrupt')
        with self.assertRaises(ValueError):
            m.validate(self.manifest, self.root)

    def test_duplicate_or_missing_artifact_rejected(self):
        self.manifest['artifacts'][-1] = self.manifest['artifacts'][0]
        with self.assertRaises(ValueError):
            m.validate(self.manifest, self.root)

    def test_failed_or_dirty_report_rejected(self):
        report = self.report()
        report['status'] = 'failed'
        with self.assertRaises(ValueError):
            m.merge(self.manifest, report, self.root)
        report['status'] = 'passed'
        report['artifacts'][0]['source_dirty'] = True
        with self.assertRaises(ValueError):
            m.merge(self.manifest, report, self.root)

    def test_lfs_pointer_rejected_even_with_matching_hash(self):
        e = self.manifest['artifacts'][0]
        path = self.root / e['filename']
        path.write_bytes(b'version https://git-lfs.github.com/spec/v1\n')
        e.update(bytes=path.stat().st_size, sha256=m.digest(path))
        with self.assertRaises(ValueError):
            m.check_entry(e, self.root)

    def test_path_traversal_rejected(self):
        report = self.report()
        report['artifacts'][0]['filename'] = '../oops'
        with self.assertRaises(ValueError):
            m.merge(self.manifest, report, self.root)


if __name__ == '__main__':
    unittest.main()
