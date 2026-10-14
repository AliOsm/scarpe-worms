#!/usr/bin/env python3
"""Release safety regressions: python3 -I tools/test_release.py."""
from pathlib import Path
import importlib.util
import json
import os
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('release', Path(__file__).with_name('release.py'))
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='release-regression-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.addCleanup(patch.stopall)
        patch.object(release, 'ROOT', self.root).start()
        patch.dict(os.environ, GITHUB_REPOSITORY='AliOsm/scarpe-worms', GITHUB_RUN_ID='123').start()
        self.git('init', '-q')
        self.git('config', 'user.name', 'Release test')
        self.git('config', 'user.email', 'release@example.invalid')
        (self.root / 'lib').mkdir()
        (self.root / 'lib/burrow.rb').write_text('module Burrow\n  VERSION = "0.5.4"\n  PROTOCOL = 4\nend\n')
        (self.root / 'packaging/server').mkdir(parents=True)
        (self.root / 'packaging/server/compose.yaml').write_text(
            'services:\n  burrow:\n    image: ${BURROW_IMAGE:?Set BURROW_IMAGE in .env}\n')
        self.git('add', '.')
        self.git('commit', '-qm', 'Test source')
        self.tag = 'test-rel-0.5.4-regression'
        self.git('tag', self.tag)
        self.meta = release.metadata(self.tag, True)
        self.artifacts = self.root / 'artifacts'
        for group, names in release.package_names('0.5.4').items():
            if group == 'linux':
                names = {name for name in names if name.endswith('.tar.gz')}
            directory = self.artifacts / f'burrow-brigade-{group}'
            directory.mkdir(parents=True)
            for name in names:
                path = directory / name
                path.write_text(f'Only a test fixture: {name}\n')
                release.write_checksum(path)
        self.output = self.root / 'output'
        self.notes = self.root / 'notes.md'

    def git(self, *args):
        return subprocess.check_output(['git', *args], cwd=self.root, text=True).strip()

    def assemble(self):
        release.assemble(self.meta, self.artifacts, self.output, self.notes)

    def test_test_tag_cannot_publish(self):
        with self.assertRaisesRegex(ValueError, 'must remain drafts'):
            release.metadata(self.tag, False)

    def test_mismatched_version_and_moved_tag_rejected(self):
        self.git('tag', 'v0.5.3')
        with self.assertRaisesRegex(ValueError, 'does not match'):
            release.metadata('v0.5.3', True)
        with self.assertRaisesRegex(ValueError, 'tag moved'):
            release.metadata(self.tag, True, '0' * 40)

    def test_annotated_tag_resolves_to_commit(self):
        self.git('tag', '-a', 'v0.5.4', '-m', 'Release')
        self.assertEqual(self.meta['sha'], release.metadata('v0.5.4', False)['sha'])

    def test_complete_release_and_notes(self):
        self.assemble()
        self.assertEqual(18, len(release.verify_assets(self.meta, self.output)))
        self.assertIn(':-ghcr.io/aliosm/burrow-brigade:0.5.4', (self.output / 'compose.yaml').read_text())
        notes = self.notes.read_text()
        for text in ('0.5.4', 'protocol 4', '4388', 'fingerprint', 'Gatekeeper', 'SmartScreen', 'Linux',
                     'docker load', 'docker run', 'docker compose', 'SHA256SUMS', 'Test source'):
            self.assertIn(text, notes)

    def test_missing_platform_rejected(self):
        directory = self.artifacts / 'burrow-brigade-linux'
        for path in directory.iterdir():
            path.unlink()
        with self.assertRaisesRegex(ValueError, 'missing linux'):
            self.assemble()

    def test_corrupt_asset_rejected_before_publication(self):
        path = next((self.artifacts / 'burrow-brigade-macos').glob('*.zip'))
        path.write_bytes(path.read_bytes() + b'corrupt')
        with self.assertRaisesRegex(ValueError, 'Checksum'):
            self.assemble()

    def test_checksum_cannot_name_another_file(self):
        path = next((self.artifacts / 'burrow-brigade-macos').glob('*.sha256'))
        path.write_text(path.read_text().split()[0] + '  ../other.zip\n')
        with self.assertRaisesRegex(ValueError, 'filename mismatch'):
            self.assemble()

    def test_unexpected_and_symlink_assets_rejected(self):
        directory = self.artifacts / 'burrow-brigade-macos'
        path = next(directory.glob('*.zip'))
        path.unlink()
        path.symlink_to(self.root / 'lib/burrow.rb')
        with self.assertRaisesRegex(ValueError, 'symlink'):
            self.assemble()

    def test_tampered_assembled_directory_never_calls_github(self):
        self.assemble()
        (self.output / 'compose.yaml').write_text('corrupt')
        with patch.object(release, 'run') as commands:
            with self.assertRaises(ValueError):
                release.publish(self.meta, self.output, self.notes)
            commands.assert_not_called()

    def test_bad_uploaded_digest_keeps_release_draft(self):
        self.git('tag', 'v0.5.4')
        self.meta = release.metadata('v0.5.4', False)
        self.assemble()
        assets = [dict(name=p.name, state='uploaded', size=p.stat().st_size, digest='sha256:' + '0' * 64)
                  for p in self.output.iterdir()]
        calls = []

        def command(*args):
            calls.append(args)
            if '--slurp' in args:
                return '[[]]'
            if args[:3] == ('gh', 'release', 'view'):
                return '{"databaseId": 1}'
            if args[:2] == ('gh', 'api'):
                return json.dumps(dict(draft=True, assets=assets))
            return ''

        with patch.object(release, 'remote_tag'), patch.object(release, 'run', side_effect=command):
            with self.assertRaisesRegex(ValueError, 'Uploaded checksum mismatch'):
                release.publish(self.meta, self.output, self.notes)
        self.assertFalse(any('--draft=false' in args for args in calls))

    def test_publication_is_last_and_requires_verified_uploads(self):
        self.git('tag', 'v0.5.4')
        self.meta = release.metadata('v0.5.4', False)
        self.assemble()
        assets = [dict(name=p.name, state='uploaded', size=p.stat().st_size, digest='sha256:' + release.digest(p))
                  for p in self.output.iterdir()]
        calls = []
        published = False

        def command(*args):
            nonlocal published
            calls.append(args)
            if '--slurp' in args:
                return '[[]]'
            if args[:3] == ('gh', 'release', 'view'):
                return '{"databaseId": 1}'
            if '--draft=false' in args:
                published = True
            if args[:2] == ('gh', 'api'):
                return json.dumps(dict(draft=not published, assets=assets, html_url='https://example.invalid/release'))
            return ''

        with patch.object(release, 'remote_tag') as remote, patch.object(release, 'run', side_effect=command):
            release.publish(self.meta, self.output, self.notes)
        self.assertEqual(2, remote.call_count)
        self.assertIn('--draft=false', calls[-2])
        self.assertTrue(published)

    def test_draft_rerun_clobbers_assets_and_removes_obsolete_asset(self):
        self.assemble()
        assets = [dict(name=p.name, state='uploaded', size=p.stat().st_size, digest='sha256:' + release.digest(p))
                  for p in self.output.iterdir()]
        calls = []

        def command(*args):
            calls.append(args)
            if '--slurp' in args:
                return json.dumps([[dict(tag_name=self.tag, assets=[dict(name='obsolete.zip', id=7)])]])
            if args[:3] == ('gh', 'release', 'view'):
                return '{"databaseId": 1}'
            if args[:2] == ('gh', 'api') and '--method' not in args:
                return json.dumps(dict(draft=True, assets=assets, html_url='https://example.invalid/draft'))
            return ''

        with patch.object(release, 'remote_tag'), patch.object(release, 'run', side_effect=command):
            release.publish(self.meta, self.output, self.notes)
        self.assertTrue(any('--clobber' in args for args in calls))
        self.assertTrue(any('DELETE' in args for args in calls))
        self.assertFalse(any('--draft=false' in args for args in calls))
        self.assertFalse(any('/releases/tags/' in value for args in calls for value in args))


if __name__ == '__main__':
    unittest.main()
