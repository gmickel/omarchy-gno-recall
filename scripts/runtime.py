#!/usr/bin/python3
"""Install and verify the reviewed GNO runtime. Python stdlib only; no install hooks."""
import base64
import concurrent.futures
import contextlib
import fcntl
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import platform
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
import urllib.request

PLUGIN = Path(__file__).resolve().parent.parent
MANIFEST = PLUGIN / 'runtime' / 'trust-manifest.json'
BUN = 'node_modules/@oven/bun-linux-x64-baseline/bin/bun'
GNO = 'node_modules/@gmickel/gno/src/index.ts'
DOWNLOAD_DEADLINE = 300
DISCOVERY_LIMIT = 2 * 1024 ** 3
DOWNLOAD_CHUNK = 64 * 1024


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def tree_digest(root):
    """Hash every directory and file, including paths and normalized permissions."""
    result = hashlib.sha256()
    for path in sorted(root.rglob('*')):
        info = path.lstat()
        rel = path.relative_to(root).as_posix()
        if info.st_uid != os.getuid() or info.st_mode & 0o022:
            raise ValueError('unsafe runtime ownership/permissions: ' + rel)
        if stat.S_ISLNK(info.st_mode) or not (path.is_file() or path.is_dir()):
            raise ValueError('unsupported runtime entry: ' + rel)
        kind = 'd' if path.is_dir() else 'f'
        value = '' if kind == 'd' else digest(path)
        result.update(f'{kind}\0{rel}\0{stat.S_IMODE(info.st_mode):o}\0{value}\n'.encode())
    return result.hexdigest()


def safe_directory(path):
    path = path.absolute()
    for part in [*reversed(path.parents), path]:
        if part.is_symlink():
            raise ValueError('symlink directory refused: ' + str(part))
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    info = path.stat()
    if info.st_uid != os.getuid() or info.st_mode & 0o022:
        raise ValueError('unsafe directory ownership/permissions: ' + str(path))
    return path


def manifest():
    raw = MANIFEST.read_bytes()
    data = json.loads(raw)
    if data['schema'] != 1 or platform.system() != 'Linux' or platform.machine() != 'x86_64':
        raise ValueError('this runtime supports Linux x86_64 (glibc) only')
    return data, hashlib.sha256(raw).hexdigest()[:24]


def location(identity):
    base = Path(os.environ.get('XDG_DATA_HOME', str(Path.home() / '.local/share')))
    if not base.is_absolute():
        raise ValueError('XDG_DATA_HOME must be absolute')
    return base / 'gno-recall' / 'runtimes' / identity


@contextlib.contextmanager
def locked(root, exclusive=False):
    safe_directory(root.parent)
    lock = root.parent / (root.name + '.lock')
    fd = os.open(lock, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        info = os.fstat(fd)
        if info.st_uid != os.getuid() or info.st_mode & 0o077 or not stat.S_ISREG(info.st_mode):
            raise ValueError('unsafe runtime lock')
        fcntl.flock(fd, fcntl.LOCK_EX if exclusive else fcntl.LOCK_SH)
        yield fd
    finally:
        os.close(fd)


def unpack(archive, target):
    target.mkdir(parents=True, exist_ok=True)
    target.chmod(0o755)
    with tarfile.open(archive, 'r:gz') as tar:
        prefix = None
        for member in tar:
            parts = PurePosixPath(member.name).parts
            if parts and prefix is None:
                prefix = parts[0]
            if len(parts) == 1 and member.isdir():
                continue
            if not parts or parts[0] != prefix or '..' in parts or member.name.startswith('/'):
                raise ValueError('unsafe archive path: ' + member.name)
            rel = Path(*parts[1:])
            if not rel.parts or not (member.isfile() or member.isdir()):
                raise ValueError('unsupported archive entry: ' + member.name + ' type=' + repr(member.type))
            path = target / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            if member.isdir():
                path.mkdir(exist_ok=True)
                path.chmod(0o755)
            else:
                # Exact pinned tarballs may repeat regular entries (npm agent-base).
                # Match tar last-entry semantics; links and special files stay forbidden.
                with path.open('wb') as out, tar.extractfile(member) as source:
                    shutil.copyfileobj(source, out)
                path.chmod(0o755 if member.mode & 0o111 else 0o644)


def artifact_size(artifact):
    size = artifact.get('sizeBytes')
    if type(size) is not int or size <= 0:
        raise ValueError('artifact sizeBytes must be a positive integer: ' + artifact['path'])
    return size


def download(artifact, archive, measure):
    """Child process: stream within the byte budget and verify before returning."""
    limit = DISCOVERY_LIMIT if measure else artifact_size(artifact)
    algorithm, encoded = artifact['integrity'].split('-', 1)
    if algorithm not in ('sha512', 'sha256'):
        raise ValueError('unsupported artifact digest')
    expected = base64.b64decode(encoded, validate=True)
    if len(expected) != hashlib.new(algorithm).digest_size:
        raise ValueError('invalid artifact digest length')
    if not artifact['url'].startswith('https://'):
        raise ValueError('artifact must use HTTPS')
    request = urllib.request.Request(artifact['url'], headers={'User-Agent': 'gno-recall-runtime/1'})
    total = 0
    checksum = hashlib.new(algorithm)
    with urllib.request.urlopen(request, timeout=120) as response, archive.open('wb') as out:
        if not response.url.startswith('https://'):
            raise ValueError('insecure artifact redirect')
        length = response.headers.get('Content-Length')
        if length is not None:
            if not length.isascii() or not length.isdecimal():
                raise ValueError('invalid artifact size header')
            if int(length) > limit or (not measure and int(length) != limit):
                raise ValueError('artifact size header mismatch: ' + artifact['path'])
        while True:
            chunk = response.read(min(DOWNLOAD_CHUNK, limit - total + 1))
            if not chunk:
                break
            total += len(chunk)
            if total > limit:
                raise ValueError('artifact size exceeds limit: ' + artifact['path'])
            out.write(chunk)
            checksum.update(chunk)
    if total == 0 or (not measure and total != limit):
        raise ValueError('artifact size mismatch (truncated): ' + artifact['path'])
    if checksum.digest() != expected:
        raise ValueError('artifact checksum mismatch: ' + artifact['path'])


def fetch(artifact, cache, *, measure=False, deadline=DOWNLOAD_DEADLINE):
    if not measure:
        artifact_size(artifact)
    archive = cache / hashlib.sha256((artifact['url'] + artifact['integrity']).encode()).hexdigest()
    try:
        # A process boundary enforces elapsed time even inside DNS/TLS/header reads.
        # subprocess.run kills and reaps on timeout before partial-file cleanup.
        result = subprocess.run([sys.executable, '-I', str(Path(__file__).resolve()), '_download'],
                                input=json.dumps([artifact, str(archive), measure]), text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=deadline)
        if result.returncode:
            raise ValueError(result.stderr.strip() or 'artifact download failed: ' + artifact['path'])
        if measure:
            artifact['sizeBytes'] = archive.stat().st_size
        return artifact, archive
    except subprocess.TimeoutExpired as error:
        archive.unlink(missing_ok=True)
        raise ValueError('artifact download deadline exceeded: ' + artifact['path']) from error
    except BaseException:
        archive.unlink(missing_ok=True)
        raise


def assemble(data, root, cache, *, measure=False):
    # Nested dependencies may share archives; fetch each once to avoid cache races.
    unique = {}
    for artifact in data['artifacts']:
        key = (artifact['url'], artifact['integrity'])
        if not measure:
            size = artifact_size(artifact)
            if key in unique and size != artifact_size(unique[key]):
                raise ValueError('conflicting artifact sizes: ' + artifact['path'])
        unique[key] = artifact
    downloaded = {}
    # Submit at most eight transfers; a failed batch never starts the remaining queue.
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        remaining = iter(unique.items())
        pending = {}
        def submit_next():
            item = next(remaining, None)
            if item is not None:
                key, artifact = item
                kwargs = {'measure': True} if measure else {}
                pending[pool.submit(fetch, artifact, cache, **kwargs)] = key
        for _ in range(8):
            submit_next()
        while pending:
            finished, _ = concurrent.futures.wait(pending, return_when=concurrent.futures.FIRST_COMPLETED)
            for future in finished:
                key = pending.pop(future)
                _, archive = future.result()
                downloaded[key] = archive
            for _ in finished:
                submit_next()
    if measure:
        for artifact in data['artifacts']:
            artifact['sizeBytes'] = unique[(artifact['url'], artifact['integrity'])]['sizeBytes']
    for artifact in sorted(data['artifacts'], key=lambda a: a['path']):
        archive = downloaded[(artifact['url'], artifact['integrity'])]
        rel = PurePosixPath(artifact['path'])
        if rel.is_absolute() or '..' in rel.parts or rel.parts[0] != 'node_modules':
            raise ValueError('unsafe package target')
        try:
            unpack(archive, root / artifact['path'])
        except ValueError as error:
            raise ValueError(artifact['path'] + ': ' + str(error)) from error
    apply_patches(data.get('patches', []), root)
    (root / 'bunfig.toml').write_text('[install]\nauto = "disable"\n')
    (root / 'package.json').write_text('{"private":true,"type":"module"}\n')
    for path in root.rglob('*'):
        if path.is_dir():
            path.chmod(0o755)
    (root / 'bunfig.toml').chmod(0o644)
    (root / 'package.json').chmod(0o644)


def apply_patches(patches, root):
    for patch in patches:
        rel = PurePosixPath(patch['path'])
        if rel.is_absolute() or '..' in rel.parts or rel.parts[0] != 'node_modules':
            raise ValueError('unsafe patch target')
        path = root / patch['path']
        if digest(path) != patch['beforeSha256']:
            raise ValueError('runtime patch source mismatch: ' + patch['path'])
        source = path.read_text()
        if source.count(patch['find']) != 1:
            raise ValueError('runtime patch must match exactly once')
        path.write_text(source.replace(patch['find'], patch['replace']))
        if digest(path) != patch['afterSha256']:
            raise ValueError('runtime patch result mismatch: ' + patch['path'])


def verify(data, root):
    if root.is_symlink() or not root.is_dir():
        raise ValueError('runtime missing; run scripts/install-runtime.sh from the plugin checkout')
    safe_directory(root)
    for parent in root.parents:
        if (parent / 'node_modules').exists() or (parent / 'node_modules').is_symlink():
            raise ValueError('external ancestor node_modules refused: ' + str(parent))
    if tree_digest(root) != data['treeSha256']:
        raise ValueError('runtime integrity check failed; run scripts/install-runtime.sh --repair')


def install(data, root, repair=False):
    with locked(root, exclusive=True):
        if root.exists() or root.is_symlink():
            try:
                verify(data, root)
                print('Verified runtime already installed: ' + str(root))
                return
            except ValueError:
                if not repair:
                    raise
        with tempfile.TemporaryDirectory(prefix='.install-', dir=root.parent) as temp:
            staging = Path(temp) / 'runtime'
            cache = Path(temp) / 'downloads'
            staging.mkdir(mode=0o700)
            cache.mkdir(mode=0o700)
            assemble(data, staging, cache)
            verify(data, staging)
            if root.exists() or root.is_symlink():
                # Explicit repair preserves evidence instead of deleting altered files.
                backup = root.with_name(root.name + '.quarantine-' + str(os.getpid()))
                root.rename(backup)
                print('Previous runtime retained at: ' + str(backup))
            staging.rename(root)
        print('Installed verified runtime: ' + str(root))


def run(data, root, args):
    with locked(root) as fd:
        verify(data, root)
        # Only data/display/locale locations cross into Bun. No NODE_OPTIONS,
        # BUN_OPTIONS, LD_PRELOAD, loader paths, or arbitrary GNO test hooks.
        allowed = {'HOME', 'USER', 'LOGNAME', 'LANG', 'LC_ALL', 'LC_CTYPE', 'TZ',
                   'XDG_CONFIG_HOME', 'XDG_DATA_HOME', 'XDG_CACHE_HOME', 'XDG_STATE_HOME',
                   'XDG_RUNTIME_DIR', 'GNO_CONFIG_DIR', 'GNO_DATA_DIR', 'GNO_CACHE_DIR',
                   'CUDA_VISIBLE_DEVICES', 'GGML_VK_VISIBLE_DEVICES'}
        env = {key: value for key, value in os.environ.items() if key in allowed}
        for key, value in env.items():
            if (key == 'HOME' or key.endswith(('_DIR', '_HOME'))) and not Path(value).is_absolute():
                raise ValueError(key + ' must be absolute')
        env.update(PATH='/usr/bin:/bin', GNO_NO_PAGER='1', GNO_LLAMA_BUILD='never',
                   NODE_LLAMA_CPP_SKIP_DOWNLOAD='true', BUN_RUNTIME_TRANSPILER_CACHE_PATH='0')
        os.chdir(root)
        # Keep the shared installer lock through Bun and its descendants.
        os.set_inheritable(fd, True)
        os.execve(root / BUN, [str(root / BUN), '--no-env-file', '--no-install',
                              '--config=' + str(root / 'bunfig.toml'), str(root / GNO), *args], env)


def main():
    if sys.argv[1:] == ['_download']:
        artifact, archive, measure = json.load(sys.stdin)
        download(artifact, Path(archive), measure)
        return
    data, identity = manifest()
    root = location(identity)
    command, *args = sys.argv[1:]
    if command == 'install' and args in ([], ['--repair']):
        install(data, root, bool(args))
    elif command == 'check' and not args:
        with locked(root):
            verify(data, root)
        print(root)
    elif command == 'run':
        run(data, root, args)
    else:
        raise ValueError('usage: runtime.py install [--repair] | check | run <gno arguments>')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, KeyError, tarfile.TarError) as error:
        message = 'GNO Recall: ' + str(error)
        if len(sys.argv) > 1 and sys.argv[1] == 'run':
            print(json.dumps({'error': {'code': 'RUNTIME', 'message': message}}), file=sys.stderr)
        else:
            print(message, file=sys.stderr)
        sys.exit(78)
