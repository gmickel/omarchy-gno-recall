#!/usr/bin/python3
"""Exercise the installed pinned runtime against disposable synthetic documents."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--models-dir', type=Path, help='Read existing GGUF files to also test cold model metadata and deep search')
options = parser.parse_args()

launcher = Path(__file__).resolve().parent / 'verified-gno.sh'
with tempfile.TemporaryDirectory(prefix='gno-recall-smoke-') as temp:
    root = Path(temp)
    env = dict(os.environ, GNO_CONFIG_DIR=str(root / 'config'),
               GNO_DATA_DIR=str(root / 'data'), GNO_CACHE_DIR=str(root / 'cache'))
    if options.models_dir:
        models = root / 'cache/models'
        models.mkdir(parents=True)
        sources = list(options.models_dir.glob('*.gguf'))
        assert sources, '--models-dir contains no GGUF files'
        for source in sources:
            (models / source.name).symlink_to(source.resolve())
    docs = root / 'docs'
    docs.mkdir()
    (docs / 'fixture.md').write_text('# Recall fixture\n\nCopper orchard lantern is the synthetic acceptance phrase.\n')

    def run(*args, structured=False):
        started = time.monotonic()
        result = subprocess.run([str(launcher), *args], env=env, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=90)
        assert result.returncode == 0, (args, result.returncode, result.stderr)
        print(f'{args[0]}: passed ({time.monotonic() - started:.2f}s)')
        return json.loads(result.stdout) if structured else result.stdout

    expected = json.loads((launcher.parent.parent / 'runtime/manifest.json').read_text())['gnoVersion']
    assert run('--version').strip() == expected
    run('init', str(docs), '--name', 'recall-smoke')
    if options.models_dir:
        run('index')
    else:
        run('index', '--no-embed')
    peek = run('peek', '--json', structured=True)
    assert peek['initialized'] and peek['counts']['documents'] == 1
    status = run('status', '--json', structured=True)
    assert 'recall-smoke' in json.dumps(status)
    listing = run('ls', 'recall-smoke', '--json', '-n', '50', structured=True)
    assert 'fixture.md' in json.dumps(listing)
    # Hostile inherited launch configuration cannot inject code before verification.
    injected = root / 'injected'
    preload = root / 'preload.sh'
    preload.write_text('touch "' + str(injected) + '"\n')
    fake = root / 'bin'
    fake.mkdir()
    for name in ['gno', 'bun', 'dirname', 'readlink', 'python3']:
        path = fake / name
        path.write_text('#!/bin/sh\ntouch "' + str(injected) + '"\nexit 1\n')
        path.chmod(0o755)
    saved_env = env.copy()
    env.update(PATH=str(fake), BASH_ENV=str(preload), NODE_OPTIONS='--require=/untrusted',
               BUN_OPTIONS='--preload=/untrusted')
    assert run('--version').strip() == expected
    assert not injected.exists(), 'inherited PATH/BASH_ENV executed untrusted code'
    env = saved_env
    queryfile = root / 'query.txt' 
    queryfile.write_text('copper orchard lantern')
    hits = run('search', '--query-file', str(queryfile), '--json', '--no-project-affinity', '-n', '20', structured=True)
    assert 'fixture.md' in json.dumps(hits)
    if options.models_dir:
        deep = run('query', '--query-file', str(queryfile), '--json', '--no-project-affinity', '-n', '20', structured=True)
        assert 'fixture.md' in json.dumps(deep)
print('Pinned runtime synthetic smoke passed' + (' including cold model metadata/deep search.' if options.models_dir else '; model-backed deep search requires --models-dir or native QA.'))
