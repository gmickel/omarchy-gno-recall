#!/usr/bin/python3
"""Regression checks for the runtime trust boundary; all files are synthetic."""
import hashlib
import io
import os
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest import mock
import runtime


class RuntimeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / 'runtime'
        self.root.mkdir(mode=0o700)
        for rel in (runtime.BUN, runtime.GNO, 'node_modules/dependency/native.node'):
            path = self.root / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('trusted fixture\n')
        self.data = {'treeSha256': runtime.tree_digest(self.root)}

    def test_integrity_failure_matrix(self):
        cases = ['bun', 'gno', 'dependency', 'missing', 'extra', 'link', 'permissions', 'ownership']
        for case in cases:
            with self.subTest(case=case), tempfile.TemporaryDirectory() as temp:
                import shutil
                root = Path(temp) / 'copy'
                shutil.copytree(self.root, root)
                target = root / runtime.BUN
                if case == 'bun': target.write_text('changed interpreter')
                if case == 'gno': (root / runtime.GNO).write_text('changed source')
                if case == 'dependency': (root / 'node_modules/dependency/native.node').write_text('changed native')
                if case == 'missing': target.unlink()
                if case == 'extra': (root / 'node_modules/extra.js').write_text('unexpected module')
                if case == 'link': target.unlink(); target.symlink_to(self.root / runtime.BUN)
                if case == 'permissions': target.chmod(0o666)
                if case == 'ownership':
                    with mock.patch('os.getuid', return_value=os.getuid() + 1):
                        with self.assertRaises(ValueError): runtime.verify(self.data, root)
                    continue
                with self.assertRaises(ValueError): runtime.verify(self.data, root)

    def test_missing_root_and_ancestor_modules(self):
        with self.assertRaises(ValueError): runtime.verify(self.data, self.root / 'missing')
        (self.root.parent / 'node_modules').mkdir()
        with self.assertRaisesRegex(ValueError, 'ancestor'): runtime.verify(self.data, self.root)

    def test_root_substitution(self):
        link = self.root.parent / 'link'
        link.symlink_to(self.root, target_is_directory=True)
        with self.assertRaises(ValueError): runtime.verify(self.data, link)

    def test_verified_launch_uses_exact_bun_and_sanitized_environment(self):
        old_cwd = Path.cwd()
        self.addCleanup(os.chdir, old_cwd)
        env = {'PATH': '/fake', 'BUN_OPTIONS': '--preload=/evil', 'NODE_OPTIONS': '--require=/evil',
               'LD_PRELOAD': '/evil.so', 'GNO_LLAMA_BUILD': 'autoAttempt', 'GNO_CONFIG_DIR': '/synthetic/config'}
        with mock.patch.dict(os.environ, env), mock.patch('os.execve', side_effect=RuntimeError('executed')) as execute:
            with self.assertRaisesRegex(RuntimeError, 'executed'):
                runtime.run(self.data, self.root, ['peek', '--json'])
        binary, argv, child_env = execute.call_args.args
        self.assertEqual(binary, self.root / runtime.BUN)
        self.assertEqual(argv[-2:], ['peek', '--json'])
        self.assertIn('--config=' + str(self.root / 'bunfig.toml'), argv)
        self.assertEqual(child_env['PATH'], '/usr/bin:/bin')
        self.assertEqual(child_env['GNO_LLAMA_BUILD'], 'never')
        self.assertEqual(child_env['GNO_CONFIG_DIR'], '/synthetic/config')
        self.assertFalse(set(env) & set(child_env) - {'PATH', 'GNO_LLAMA_BUILD', 'GNO_CONFIG_DIR'})

    def test_modified_runtime_never_executes(self):
        (self.root / runtime.BUN).write_text('untrusted')
        with mock.patch('os.execve') as execute:
            with self.assertRaises(ValueError): runtime.run(self.data, self.root, ['peek'])
        execute.assert_not_called()

    def archive(self, name, content=b'fixture', kind=tarfile.REGTYPE):
        path = self.root.parent / 'fixture.tgz'
        with tarfile.open(path, 'w:gz') as out:
            member = tarfile.TarInfo(name)
            member.type = kind
            member.size = len(content) if kind == tarfile.REGTYPE else 0
            member.linkname = '/outside'
            out.addfile(member, io.BytesIO(content))
        return path

    def test_archive_traversal_and_links_rejected(self):
        for name, kind in [('package/../../outside', tarfile.REGTYPE), ('/outside', tarfile.REGTYPE),
                           ('package/link', tarfile.SYMTYPE), ('package/link', tarfile.LNKTYPE)]:
            with self.subTest(name=name, kind=kind), tempfile.TemporaryDirectory() as t:
                with self.assertRaises(ValueError): runtime.unpack(self.archive(name, kind=kind), Path(t))

    def test_shared_archive_downloaded_once_for_nested_dependencies(self):
        archive = self.archive('package/index.js')
        first = {'path': 'node_modules/first', 'url': 'https://example.invalid/shared.tgz', 'integrity': 'sha512-fixture', 'sizeBytes': archive.stat().st_size}
        second = dict(first, path='node_modules/parent/node_modules/first')
        with mock.patch.object(runtime, 'fetch', return_value=(first, archive)) as fetch:
            runtime.assemble({'artifacts': [first, second]}, self.root, self.root.parent)
        self.assertEqual(fetch.call_count, 1)
        for artifact in [first, second]:
            self.assertEqual((self.root / artifact['path'] / 'index.js').read_bytes(), b'fixture')

    def test_install_idempotence_and_explicit_repair(self):
        with mock.patch.object(runtime, 'assemble') as assemble:
            runtime.install(self.data, self.root)
            assemble.assert_not_called()
            (self.root / runtime.BUN).write_text('tampered')
            with self.assertRaises(ValueError): runtime.install(self.data, self.root)
            assemble.assert_not_called()

    def test_reviewed_patch_requires_exact_source_and_result(self):
        source = self.root / runtime.GNO
        before = source.read_text()
        after = before.replace('trusted', 'patched')
        patch = {'path': runtime.GNO, 'find': 'trusted', 'replace': 'patched',
                 'beforeSha256': hashlib.sha256(before.encode()).hexdigest(),
                 'afterSha256': hashlib.sha256(after.encode()).hexdigest()}
        runtime.apply_patches([patch], self.root)
        self.assertEqual(source.read_text(), after)
        for field in ['beforeSha256', 'afterSha256']:
            source.write_text(before)
            bad = dict(patch, **{field: '0' * 64})
            with self.subTest(field=field), self.assertRaises(ValueError):
                runtime.apply_patches([bad], self.root)

    def test_launcher_errors_use_service_runtime_envelope(self):
        import json
        import subprocess
        result = subprocess.run([str(runtime.PLUGIN / 'scripts/verified-gno.sh'), 'peek', '--json'],
                                env=dict(os.environ, XDG_DATA_HOME=str(self.root)),
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 78)
        self.assertEqual(result.stdout, '')
        error = json.loads(result.stderr)['error']
        self.assertEqual(error['code'], 'RUNTIME')
        self.assertIn('runtime missing', error['message'])

    def test_manifest_provenance_matches_committed_lock(self):
        import json
        data = json.loads(runtime.MANIFEST.read_text())
        lock = json.loads((runtime.PLUGIN / 'runtime/package-lock.json').read_text())['packages']
        self.assertEqual(len(data['treeSha256']), 64)
        self.assertEqual(data['patches'], json.loads((runtime.PLUGIN / 'runtime/patches.json').read_text()))
        self.assertEqual(data['gnoVersion'], lock['node_modules/@gmickel/gno']['version'])
        self.assertEqual(data['bunVersion'], lock['node_modules/@oven/bun-linux-x64-baseline']['version'])
        self.assertEqual(len(data['artifacts']), len({a['path'] for a in data['artifacts']}))
        for artifact in data['artifacts']:
            self.assertIs(type(artifact['sizeBytes']), int)
            self.assertGreater(artifact['sizeBytes'], 0)
            self.assertEqual(artifact['integrity'], lock[artifact['path']]['integrity'])
            self.assertEqual(artifact['url'], lock[artifact['path']]['resolved'])
            self.assertEqual(artifact['version'], lock[artifact['path']]['version'])

    def test_repair_preserves_old_tree_until_verified_replacement(self):
        import shutil
        good = self.root.parent / 'good'
        shutil.copytree(self.root, good)
        (self.root / runtime.BUN).write_text('tampered')
        with mock.patch.object(runtime, 'assemble', side_effect=ValueError('download failed')):
            with self.assertRaisesRegex(ValueError, 'download failed'):
                runtime.install(self.data, self.root, repair=True)
        self.assertEqual((self.root / runtime.BUN).read_text(), 'tampered')
        def assemble(_data, staging, _cache):
            shutil.copytree(good, staging, dirs_exist_ok=True)
        with mock.patch.object(runtime, 'assemble', side_effect=assemble):
            runtime.install(self.data, self.root, repair=True)
        runtime.verify(self.data, self.root)
        backups = list(self.root.parent.glob('runtime.quarantine-*'))
        self.assertEqual(len(backups), 1)
        self.assertEqual((backups[0] / runtime.BUN).read_text(), 'tampered')


if __name__ == '__main__':
    unittest.main()
