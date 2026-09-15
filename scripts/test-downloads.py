#!/usr/bin/python3
"""Local TLS adversarial transfers exercise real sockets and the download watchdog."""
import base64
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import io
import os
from pathlib import Path
import socket
import ssl
import subprocess
import tempfile
import threading
import time
import unittest
from unittest import mock
import runtime

BODY = b'bounded archive fixture'


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def do_GET(self):
        mode = self.path[1:]
        try:
            if mode == 'stall-headers':
                time.sleep(3)
            if mode == 'drip-headers':
                for byte in b'HTTP/1.1 200 OK\r\nX-Drip: ' + b'x' * 100:
                    self.wfile.write(bytes([byte])); self.wfile.flush(); time.sleep(.03)
                return
            self.send_response(200)
            if mode == 'discovery-too-large':
                self.send_header('Content-Length', str(runtime.DISCOVERY_LIMIT + 1))
            elif mode == 'lying-length':
                self.send_header('Content-Length', str(len(BODY) + 10))
            elif mode == 'short-length':
                self.send_header('Content-Length', str(len(BODY) - 1))
            elif mode == 'exact':
                self.send_header('Content-Length', str(len(BODY)))
            self.end_headers()
            if mode == 'stall-body':
                time.sleep(3)
            if mode == 'drip-body':
                for byte in BODY:
                    self.wfile.write(bytes([byte])); self.wfile.flush(); time.sleep(.03)
                return
            body = BODY + b'overflow' if mode == 'oversized' else BODY
            if mode == 'short':
                body = BODY[:-1]
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError, ssl.SSLError):
            pass


class DownloadTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.root = Path(cls.temp.name)
        cert, key = cls.root / 'cert.pem', cls.root / 'key.pem'
        subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
                        '-keyout', str(key), '-out', str(cert), '-days', '1',
                        '-subj', '/CN=localhost', '-addext', 'subjectAltName=DNS:localhost'],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)
        cls.server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(cert, key)
        cls.server.socket = context.wrap_socket(cls.server.socket, server_side=True)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.env = mock.patch.dict(os.environ, SSL_CERT_FILE=str(cert), no_proxy='localhost')
        cls.env.start()

    @classmethod
    def tearDownClass(cls):
        cls.env.stop()
        cls.server.shutdown(); cls.server.server_close(); cls.thread.join()
        cls.temp.cleanup()

    def setUp(self):
        self.cache_temp = tempfile.TemporaryDirectory(dir=self.root)
        self.addCleanup(self.cache_temp.cleanup)
        self.cache = Path(self.cache_temp.name)

    def artifact(self, mode):
        return {'path': 'node_modules/test', 'url': f'https://localhost:{self.server.server_port}/{mode}',
                'integrity': 'sha512-' + base64.b64encode(hashlib.sha512(BODY).digest()).decode(),
                'sizeBytes': len(BODY)}

    def test_exact_transfer_with_and_without_length(self):
        for mode in ['exact', 'no-length']:
            with self.subTest(mode=mode):
                artifact, archive = runtime.fetch(self.artifact(mode), self.cache)
                self.assertEqual(archive.read_bytes(), BODY)
                self.assertEqual(archive.stat().st_size, artifact['sizeBytes'])

    def test_size_and_checksum_failures_remove_partial_download(self):
        for mode, error in [('oversized', 'size'), ('short', 'size'), ('lying-length', 'size'),
                            ('short-length', 'size'), ('checksum', 'checksum')]:
            with self.subTest(mode=mode):
                artifact = self.artifact(mode)
                if mode == 'checksum':
                    artifact['integrity'] = 'sha512-' + base64.b64encode(bytes(64)).decode()
                with self.assertRaisesRegex(ValueError, error):
                    runtime.fetch(artifact, self.cache)
                self.assertEqual(list(self.cache.iterdir()), [])

    def test_hard_deadline_interrupts_stall_and_slow_drip(self):
        for mode in ['stall-headers', 'stall-body', 'drip-headers', 'drip-body']:
            with self.subTest(mode=mode):
                started = time.monotonic()
                children = []
                popen = subprocess.Popen
                def spawn(*args, **kwargs):
                    child = popen(*args, **kwargs)
                    children.append(child)
                    return child
                with mock.patch.object(subprocess, 'Popen', side_effect=spawn):
                    with self.assertRaisesRegex(ValueError, 'deadline'):
                        runtime.fetch(self.artifact(mode), self.cache, deadline=.45)
                self.assertEqual(len(children), 1)
                self.assertIsNotNone(children[0].poll(), 'download child still alive after timeout')
                elapsed = time.monotonic() - started
                self.assertLess(elapsed, 1.5, f'{mode} outlived hard deadline: {elapsed}')
                self.assertEqual(list(self.cache.iterdir()), [])

    def test_tls_handshake_is_inside_deadline(self):
        with socket.socket() as listener:
            listener.bind(('127.0.0.1', 0)); listener.listen()
            accepted, release = threading.Event(), threading.Event()
            def stall_tls():
                with listener.accept()[0]:
                    accepted.set()
                    release.wait(3)
            thread = threading.Thread(target=stall_tls, daemon=True)
            thread.start()
            artifact = dict(self.artifact('exact'), url=f'https://localhost:{listener.getsockname()[1]}/')
            started = time.monotonic()
            try:
                with self.assertRaisesRegex(ValueError, 'deadline'):
                    runtime.fetch(artifact, self.cache, deadline=.45)
                self.assertTrue(accepted.is_set(), 'request did not reach TLS listener')
                self.assertLess(time.monotonic() - started, 1.5)
                self.assertEqual(list(self.cache.iterdir()), [])
            finally:
                release.set(); thread.join(timeout=4)

    def test_non_https_artifact_is_refused(self):
        artifact = dict(self.artifact('exact'), url='http://localhost/untrusted')
        with self.assertRaisesRegex(ValueError, 'HTTPS'):
            runtime.fetch(artifact, self.cache)
        self.assertEqual(list(self.cache.iterdir()), [])

    def test_discovery_stream_never_writes_past_ceiling(self):
        response = io.BytesIO(BODY)
        response.url = 'https://example.invalid/fixture'
        response.headers = {}
        archive = self.cache / 'partial'
        with mock.patch.object(runtime, 'DISCOVERY_LIMIT', 5):
            with mock.patch('urllib.request.urlopen', return_value=response):
                with self.assertRaisesRegex(ValueError, 'size exceeds limit'):
                    runtime.download(self.artifact('exact'), archive, measure=True)
        self.assertLessEqual(archive.stat().st_size, 5)

    def test_invalid_and_conflicting_size_rejected_before_download(self):
        for size in [None, 0, -1, True, '24', 1.5]:
            artifact = dict(self.artifact('exact'), sizeBytes=size)
            with self.subTest(size=size), self.assertRaisesRegex(ValueError, 'size'):
                runtime.fetch(artifact, self.cache)
        first = self.artifact('exact')
        second = dict(first, path='node_modules/nested/test', sizeBytes=first['sizeBytes'] + 1)
        with mock.patch.object(runtime, 'fetch') as fetch:
            with self.assertRaisesRegex(ValueError, 'conflicting'):
                runtime.assemble({'artifacts': [first, second]}, self.cache / 'staging', self.cache)
            fetch.assert_not_called()

    def test_measured_size_only_after_verified_bounded_download(self):
        artifact = self.artifact('no-length')
        del artifact['sizeBytes']
        runtime.fetch(artifact, self.cache, measure=True)
        self.assertEqual(artifact['sizeBytes'], len(BODY))
        artifact = self.artifact('checksum')
        del artifact['sizeBytes']
        artifact['integrity'] = 'sha512-' + base64.b64encode(bytes(64)).decode()
        with self.assertRaisesRegex(ValueError, 'checksum'):
            runtime.fetch(artifact, self.cache, measure=True)
        self.assertNotIn('sizeBytes', artifact)
        artifact = self.artifact('discovery-too-large')
        del artifact['sizeBytes']
        with self.assertRaisesRegex(ValueError, 'size'):
            runtime.fetch(artifact, self.cache, measure=True)
        self.assertNotIn('sizeBytes', artifact)

    def test_failed_batch_does_not_start_remaining_downloads(self):
        artifacts = [dict(self.artifact('exact'), url=f'https://example.invalid/{i}') for i in range(40)]
        def fetch(artifact, _cache):
            if artifact is artifacts[0]:
                raise ValueError('fixture download failure')
            time.sleep(.1)
            return artifact, self.cache / 'unused'
        with mock.patch.object(runtime, 'fetch', side_effect=fetch) as download:
            with self.assertRaisesRegex(ValueError, 'fixture download failure'):
                runtime.assemble({'artifacts': artifacts}, self.cache / 'unused', self.cache)
        self.assertLessEqual(download.call_count, 8)

    def test_failed_transfer_preserves_install_and_cleans_staging(self):
        fetch = runtime.fetch
        for existing, mode in [(False, 'oversized'), (True, 'oversized'),
                               (False, 'stall-body'), (True, 'stall-body')]:
            with self.subTest(existing=existing, mode=mode):
                root = self.cache / (mode + ('-old' if existing else '-new'))
                if existing:
                    root.mkdir(); (root / 'keep').write_text('previous runtime')
                data = {'treeSha256': 'invalid', 'artifacts': [self.artifact(mode)]}
                def short_deadline(artifact, cache):
                    return fetch(artifact, cache, deadline=.45)
                with mock.patch.object(runtime, 'fetch', side_effect=short_deadline):
                    with self.assertRaisesRegex(ValueError, 'size|deadline'):
                        runtime.install(data, root, repair=True)
                if existing:
                    self.assertEqual((root / 'keep').read_text(), 'previous runtime')
                else:
                    self.assertFalse(root.exists())
                self.assertEqual(list(self.cache.glob('.install-*')), [])
                self.assertEqual(list(self.cache.glob('*.quarantine-*')), [])


if __name__ == '__main__':
    unittest.main()
