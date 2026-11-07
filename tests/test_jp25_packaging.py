"""Fail-closed regressions for the release's reviewed source-byte contract."""
import io
import sys
import tempfile
import unittest
from pathlib import Path
from zipfile import ZipFile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import audit_jp_release as audit
import package_jp_source as package


def archive(files):
    data = io.BytesIO()
    with ZipFile(data, 'w') as output:
        for name, value in files.items():
            output.writestr(name, value)
    return ZipFile(io.BytesIO(data.getvalue()))


class ReviewedPayloadTests(unittest.TestCase):
    def setUp(self):
        self.before = {'main.lua': b'before', 'unchanged.lua': b'stable'}
        self.after = {'main.lua': b'after', 'unchanged.lua': b'stable', 'feature.lua': b'feature'}
        self.review = {
            'added': {'feature.lua': audit.sha(b'feature')},
            'changed': {'main.lua': {'before': audit.sha(b'before'), 'after': audit.sha(b'after')}},
        }

    def verify(self, before=None, after=None):
        with archive(self.before if before is None else before) as old, \
             archive(self.after if after is None else after) as new:
            return audit.verify_reviewed_changes(old, new, self.review, 'synthetic')

    def test_reviewed_change_and_addition_accepted(self):
        self.assertEqual(self.verify()['unchanged_count'], 1)

    def test_unreviewed_edits_and_wrong_baseline_rejected(self):
        with self.assertRaisesRegex(AssertionError, 'unreviewed changed bytes'):
            self.verify(after={**self.after, 'main.lua': b'changed after review'})
        with self.assertRaisesRegex(AssertionError, 'unreviewed new bytes'):
            self.verify(after={**self.after, 'feature.lua': b'changed after review'})
        with self.assertRaisesRegex(AssertionError, 'wrong review baseline'):
            self.verify(before={**self.before, 'main.lua': b'wrong baseline'})

    def test_extra_missing_and_removed_files_rejected(self):
        for change in (
            {**self.after, 'extra.lua': b'extra'},
            {name: value for name, value in self.after.items() if name != 'feature.lua'},
            {name: value for name, value in self.after.items() if name != 'unchanged.lua'},
            {**self.after, 'unchanged.lua': b'unrelated change'},
        ):
            with self.subTest(change=change), self.assertRaises(AssertionError):
                self.verify(after=change)

    def test_loading_fixture_trees_excluded_from_release_evidence(self):
        retained = {
            'loading/after/output/summary.json',
            'loading/before/output/render.png',
            'loading/baseline/output/timings.log',
            'loading/comparison.json',
            'trainer-cross-cards/jp27-cross-receipt.json',
            'trainer-cross-clock/phase-results.json',
            'foreground-clip/receipt.json',
            'action-camera/camera-motion.mp4',
        }
        excluded = {
            'loading/after/app/assets/catalog.json',
            'loading/after/save/love/options.txt',
            'loading/baseline/app/data/maps.json',
            'loading/baseline/save/love/private.png',
            'loading/before/app/README.md',
            'other/app2/assets/catalog.json',
            'other/qa-app/assets/catalog.json',
            'other/qa-save/love/options.txt',
            'trainer-render/old-results.json',
            'trainer-focus-regression/old-frame.png',
            'clearance/prototype-results.json',
            'build/source-audit.json', 'build/source-audit.log',
            'build/release-receipt.json', 'build/source-package.log',
        }
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for name in retained | excluded:
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('synthetic')
            (root / 'linked-results').symlink_to(root / 'loading/after/output', target_is_directory=True)
            self.assertEqual(set(package.evidence_files_for_package(root)), retained)


if __name__ == '__main__':
    unittest.main()
