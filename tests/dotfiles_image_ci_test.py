#!/usr/bin/env python3

import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

import yaml


REPO = Path(__file__).resolve().parent.parent
WORKFLOW = yaml.safe_load((REPO / '.github/workflows/dotfiles-image.yml').read_text())


class ImagePublicationTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='dotfiles-image-ci.')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / 'release-source'
        self.source.mkdir()
        self.assets = self.root / 'assets'
        self.assets.mkdir()
        self.tags = self.root / 'image-tags'
        self.api_log = self.root / 'api.log'
        self.docker_log = self.root / 'docker.log'
        self.upload_log = self.root / 'uploads.log'
        shutil.copy(REPO / 'compose.yaml', self.source / 'compose.yaml')
        with (self.source / 'compose.yaml').open('a') as compose:
            compose.write('\n# Source from the release commit.\n')
        self.git('init', '--quiet')
        self.git('add', '.')
        self.git('-c', 'user.name=fixture', '-c', 'user.email=fixture@example.invalid',
                 'commit', '--quiet', '-m', 'release')
        self.commit = self.git('rev-parse', 'HEAD').strip()
        self.tag = 'dotfiles-' + self.commit[:12]
        self.git('tag', self.tag)
        with (self.source / 'compose.yaml').open('a') as compose:
            compose.write('# Source from the workflow branch.\n')
        self.git('add', '.')
        self.git('-c', 'user.name=fixture', '-c', 'user.email=fixture@example.invalid',
                 'commit', '--quiet', '-m', 'workflow branch')
        self.env = {
            **os.environ,
            'PATH': str(REPO / 'tests/fixtures/dotfiles-image-ci') + os.pathsep + os.environ['PATH'],
            'GH_TOKEN': 'fixture',
            'GITHUB_ACTOR': 'fixture',
            'GITHUB_REPOSITORY': 'fixture/Repo',
            'GITHUB_WORKSPACE': str(self.root),
            'GITHUB_SHA': self.git('rev-parse', 'HEAD').strip(),
            'RELEASE_TAG': self.tag,
            'PACKAGE_OWNER_TYPE': 'User',
            'TEST_COMMIT': self.commit,
            'TEST_RELEASE_ASSETS': str(self.assets),
            'TEST_IMAGE_TAGS': str(self.tags),
            'TEST_API_LOG': str(self.api_log),
            'TEST_DOCKER_LOG': str(self.docker_log),
            'TEST_UPLOAD_LOG': str(self.upload_log),
        }
        self.run_number = 0
        self.image = 'ghcr.io/fixture/repo:' + self.commit

    def git(self, *args):
        return subprocess.check_output(['git', *args], cwd=self.source, text=True,
                                       stderr=subprocess.STDOUT, timeout=10)

    def run_step(self, step):
        return subprocess.run(
            ['bash', '--noprofile', '--norc', '-e', '-o', 'pipefail', '-c', step['run']],
            cwd=self.root, env=self.env, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=10,
        )

    def run_ci(self, *args):
        return subprocess.run(
            ['bash', str(REPO / 'scripts/dotfiles-image-ci'), *args],
            cwd=self.root, env=self.env, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=10,
        )

    def run_workflow(self, expected_status=0):
        runner = self.root / f'runner-{self.run_number}'
        self.run_number += 1
        runner.mkdir()
        self.env['RUNNER_TEMP'] = str(runner)
        self.env['GITHUB_OUTPUT'] = str(runner / 'outputs')
        Path(self.env['GITHUB_OUTPUT']).touch()
        for log in (self.api_log, self.docker_log, self.upload_log):
            log.write_text('')
        steps = {step['name']: step for step in WORKFLOW['jobs']['image']['steps']}
        preflight = self.run_ci('preflight')
        if preflight.returncode:
            self.assertEqual(preflight.returncode, expected_status, preflight.stdout)
            return preflight.stdout
        outputs = dict(line.split('=', 1) for line in
                       Path(self.env['GITHUB_OUTPUT']).read_text().splitlines())
        for name in ('release_id', 'commit_sha', 'image'):
            self.env[name.upper()] = outputs[name]
        build_image = outputs['build_image'] == 'true'
        attach_compose = outputs['attach_compose'] == 'true'
        output = preflight.stdout
        status = 0
        if build_image or attach_compose:
            self.git('checkout', '--quiet', '--detach', outputs['commit_sha'])
        try:
            if build_image:
                for name in ('Sign in to GHCR', 'Build and publish the missing image'):
                    result = self.run_step(steps[name])
                    output += result.stdout
                    if result.returncode:
                        status = result.returncode
                        break
            if status == 0 and attach_compose:
                result = self.run_ci('publish-compose', str(self.source / 'compose.yaml'))
                output += result.stdout
                status = result.returncode
        finally:
            if build_image:
                cleanup = self.run_step(steps['Remove registry credentials'])
                self.assertEqual(cleanup.returncode, 0, cleanup.stdout)
        self.assertEqual(status, expected_status, output)
        return output

    def check_assets(self):
        compose = (self.assets / 'compose.yaml').read_bytes()
        expected = hashlib.sha256(compose).hexdigest() + '  compose.yaml\n'
        self.assertEqual((self.assets / 'compose.yaml.sha256').read_text(), expected)
        self.assertIn(('    image: ' + self.image).encode(), compose)
        self.assertNotIn(b'    build:', compose)
        self.assertIn(b'# Source from the release commit.', compose)
        self.assertNotIn(b'# Source from the workflow branch.', compose)

    def test_first_publication_uses_release_commit(self):
        self.run_workflow()
        self.check_assets()
        self.assertEqual(self.env['COMMIT_SHA'], self.commit)
        self.assertNotEqual(self.env['COMMIT_SHA'], self.env['GITHUB_SHA'])
        self.assertIn('push ' + self.image, self.docker_log.read_text())
        self.assertEqual(self.upload_log.read_text().splitlines(),
                         ['compose.yaml', 'compose.yaml.sha256'])

    def test_existing_image_and_assets_are_preserved(self):
        self.run_workflow()
        before = {path.name: path.read_bytes() for path in self.assets.iterdir()}
        self.run_workflow()
        self.assertEqual(before, {path.name: path.read_bytes() for path in self.assets.iterdir()})
        self.assertEqual(self.upload_log.read_text(), '')
        self.assertEqual(self.docker_log.read_text(), '')

    def test_missing_checksum_uses_existing_compose(self):
        self.run_workflow()
        (self.assets / 'compose.yaml.sha256').unlink()
        with (self.assets / 'compose.yaml').open('a') as compose:
            compose.write('# Preserve the published file.\n')
        before = (self.assets / 'compose.yaml').read_bytes()
        self.run_workflow()
        self.check_assets()
        self.assertEqual((self.assets / 'compose.yaml').read_bytes(), before)
        self.assertEqual(self.upload_log.read_text(), 'compose.yaml.sha256\n')
        self.assertEqual(self.docker_log.read_text(), '')

    def test_missing_compose_matches_existing_checksum(self):
        self.run_workflow()
        checksum = (self.assets / 'compose.yaml.sha256').read_bytes()
        (self.assets / 'compose.yaml').unlink()
        self.run_workflow()
        self.check_assets()
        self.assertEqual((self.assets / 'compose.yaml.sha256').read_bytes(), checksum)
        self.assertEqual(self.upload_log.read_text(), 'compose.yaml\n')
        self.assertEqual(self.docker_log.read_text(), '')

    def test_checksum_mismatch_prevents_upload(self):
        self.run_workflow()
        (self.assets / 'compose.yaml').unlink()
        checksum = '0' * 64 + '  compose.yaml\n'
        (self.assets / 'compose.yaml.sha256').write_text(checksum)
        self.run_workflow(expected_status=1)
        self.assertFalse((self.assets / 'compose.yaml').exists())
        self.assertEqual((self.assets / 'compose.yaml.sha256').read_text(), checksum)
        self.assertEqual(self.upload_log.read_text(), '')

    def test_interrupted_upload_is_completed_without_rebuild(self):
        self.env['TEST_UPLOAD_FAIL_AFTER_COMPOSE'] = '1'
        self.run_workflow(expected_status=77)
        self.assertTrue((self.assets / 'compose.yaml').exists())
        self.assertFalse((self.assets / 'compose.yaml.sha256').exists())
        del self.env['TEST_UPLOAD_FAIL_AFTER_COMPOSE']
        self.run_workflow()
        self.check_assets()
        self.assertNotIn('build ', self.docker_log.read_text())
        self.assertEqual(self.upload_log.read_text(), 'compose.yaml.sha256\n')

    def test_failed_latest_push_can_retry_before_commit_tag_is_published(self):
        self.env['TEST_DOCKER_FAILURE'] = 'push:latest'
        self.run_workflow(expected_status=76)
        self.assertEqual(self.upload_log.read_text(), '')
        self.assertFalse(self.tags.exists())
        del self.env['TEST_DOCKER_FAILURE']
        self.run_workflow()
        self.check_assets()
        self.assertIn('build ', self.docker_log.read_text())
        self.assertIn('push ' + self.image, self.docker_log.read_text())

    def test_workflow_gates_docker_and_checks_out_the_release_commit(self):
        steps = WORKFLOW['jobs']['image']['steps']
        for step in steps:
            if 'docker ' in step.get('run', ''):
                self.assertIn("needs.preflight.outputs.build_image == 'true'", step['if'])
            if step['name'] == 'Check out the release commit':
                self.assertEqual(step['with']['ref'], '${{ needs.preflight.outputs.commit_sha }}')

    def test_package_errors_prevent_building(self):
        for error in ('403', '500'):
            with self.subTest(error=error):
                self.env['TEST_PACKAGE_ERROR'] = error
                self.run_workflow(expected_status=1)
                self.assertNotIn('build ', self.docker_log.read_text())
                self.assertEqual(self.upload_log.read_text(), '')

    def test_missing_release_prevents_building(self):
        self.env['TEST_RELEASE_ERROR'] = '404'
        self.run_workflow(expected_status=75)
        self.assertNotIn('build ', self.docker_log.read_text())
        self.assertEqual(self.upload_log.read_text(), '')

    def test_commit_mismatch_prevents_building(self):
        self.env['TEST_COMMIT'] = '0' * 40
        self.run_workflow(expected_status=1)
        self.assertNotIn('build ', self.docker_log.read_text())

    def test_existing_organization_image_is_reused(self):
        self.env['PACKAGE_OWNER_TYPE'] = 'Organization'
        self.tags.write_text(self.commit + '\n')
        self.run_workflow()
        self.check_assets()
        self.assertIn('orgs/fixture/packages/container/repo/versions', self.api_log.read_text())
        self.assertNotIn('build ', self.docker_log.read_text())

    def test_download_failure_preserves_existing_assets(self):
        self.run_workflow()
        (self.assets / 'compose.yaml.sha256').unlink()
        before = (self.assets / 'compose.yaml').read_bytes()
        self.env['TEST_DOWNLOAD_FAIL'] = '1'
        self.run_workflow(expected_status=75)
        self.assertEqual((self.assets / 'compose.yaml').read_bytes(), before)
        self.assertFalse((self.assets / 'compose.yaml.sha256').exists())
        self.assertEqual(self.upload_log.read_text(), '')


if __name__ == '__main__':
    unittest.main()
