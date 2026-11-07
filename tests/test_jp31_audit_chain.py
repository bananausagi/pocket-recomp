"""Fail closed when any link in the retained retirement audit is missing/changed."""
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
from zipfile import ZipFile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import audit_jp_release as audit


def archive(entries):
    output = io.BytesIO()
    with ZipFile(output, 'w') as z:
        for name, value in entries.items():
            z.writestr(name, value)
    return output.getvalue()


class PreviousDeliveryChainTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.fingerprint = b'{"DRAMALESS_SHAPE":{},"VOXEL_ASCENDANT":{}}'
        self.retired = 'assets/jp-mods/upgrades-jp19.json'
        self.apk_bytes = archive({'assets/game.love': archive({self.retired: self.fingerprint})})
        self.apk = self.root / 'previous.apk'
        self.apk.write_bytes(self.apk_bytes)
        self.receipt = {
            'version': '0.2.66-jp.30', 'apk_sha256': audit.sha(self.apk_bytes),
            'base_apk_sha256': audit.BASE_SHA256,
            'jp19_retirement_fingerprints_preserved_from_verified_delivery': True,
            'jp19_retirement_evidence': {
                'method': 'previous-delivery-audit-chain',
                'jp19_apk_reaudited_this_release': False,
                'previous_audit_jp19_apk_sha256': audit.JP19_SHA256,
                'retirement_fingerprint_sha256': audit.sha(self.fingerprint),
            },
        }
        self.receipt_bytes = json.dumps(self.receipt).encode()
        self.entries = {audit.PREVIOUS_AUDIT_PATH: self.receipt_bytes,
                        'source/' + self.retired: self.fingerprint}
        self.source = self.root / 'previous-source.zip'
        self.source.write_bytes(archive(self.entries))
        self.pins = dict(PREVIOUS_SHA256=audit.sha(self.apk_bytes),
                         PREVIOUS_SOURCE_SHA256=audit.sha(self.source.read_bytes()),
                         PREVIOUS_AUDIT_SHA256=audit.sha(self.receipt_bytes))

    def verify(self):
        result = {}
        with patch.multiple(audit, **self.pins):
            audit.verify_retirement_audit_chain(self.source, self.apk, result)
        return result['jp19_retirement_evidence']

    def source_replace(self, entries):
        self.source.write_bytes(archive(entries))
        self.pins['PREVIOUS_SOURCE_SHA256'] = audit.sha(self.source.read_bytes())

    def test_chain_preserves_but_does_not_claim_fresh_archival_audit(self):
        chain = self.verify()
        self.assertEqual(chain['method'], 'previous-delivery-audit-chain')
        self.assertIs(chain['jp19_apk_reaudited_this_release'], False)
        self.assertEqual(chain['retirement_fingerprint_sha256'], audit.sha(self.fingerprint))

    def test_changed_previous_source_rejected(self):
        self.source.write_bytes(self.source.read_bytes() + b'unreviewed')
        with self.assertRaisesRegex(AssertionError, 'source ZIP'):
            self.verify()

    def test_changed_previous_apk_rejected(self):
        self.apk.write_bytes(self.apk_bytes + b'unreviewed')
        with self.assertRaisesRegex(AssertionError, 'APK'):
            self.verify()

    def test_missing_or_changed_audit_rejected(self):
        self.source_replace({'source/' + self.retired: self.fingerprint})
        with self.assertRaises(KeyError):
            self.verify()
        self.source_replace({**self.entries, audit.PREVIOUS_AUDIT_PATH: self.receipt_bytes + b' '})
        with self.assertRaisesRegex(AssertionError, 'audit bytes changed'):
            self.verify()

    def test_mismatched_retirement_source_rejected(self):
        self.source_replace({**self.entries, 'source/' + self.retired: b'{"different":true}'})
        with self.assertRaisesRegex(AssertionError, 'source/APK mismatch'):
            self.verify()

    def test_false_old_verification_rejected_even_with_matching_hashes(self):
        receipt = json.dumps({**self.receipt, 'jp19_retirement_fingerprints_preserved_from_verified_delivery': False}).encode()
        self.source_replace({**self.entries, audit.PREVIOUS_AUDIT_PATH: receipt})
        self.pins['PREVIOUS_AUDIT_SHA256'] = audit.sha(receipt)
        with self.assertRaises(AssertionError):
            self.verify()

    def test_mismatched_inherited_retirement_hash_rejected(self):
        old = self.receipt['jp19_retirement_evidence']
        record = {**self.receipt, 'jp19_retirement_evidence': {
            **old, 'retirement_fingerprint_sha256': audit.sha(b'other fingerprint')}}
        receipt = json.dumps(record).encode()
        self.source_replace({**self.entries, audit.PREVIOUS_AUDIT_PATH: receipt})
        self.pins['PREVIOUS_AUDIT_SHA256'] = audit.sha(receipt)
        with self.assertRaises(AssertionError):
            self.verify()


if __name__ == '__main__':
    unittest.main()
