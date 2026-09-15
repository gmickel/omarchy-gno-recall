#!/usr/bin/python3
"""Maintainer only: derive the reviewed trust manifest from an npm v3 lockfile."""
import argparse
import json
from pathlib import Path
import tempfile
import runtime

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('lockfile', type=Path)
parser.add_argument('--output', required=True, type=Path)
args = parser.parse_args()
lock = json.loads(args.lockfile.read_text())
if lock['lockfileVersion'] != 3:
    raise SystemExit('npm lockfileVersion 3 required')
artifacts = []
for path, package in sorted(lock['packages'].items()):
    if not path:
        continue
    if any(package.get(key) and expected not in package[key] for key, expected in [('os', 'linux'), ('cpu', 'x64'), ('libc', 'glibc')]):
        continue
    # node-llama-cpp allows x64 hosts to install cross-compile ARM packages.
    if path.startswith('node_modules/@node-llama-cpp/') and not path.startswith('node_modules/@node-llama-cpp/linux-x64'):
        continue
    if path.startswith('node_modules/@oven/') and path != 'node_modules/@oven/bun-linux-x64-baseline':
        continue
    artifacts.append({'path': path, 'version': package['version'],
                      'url': package['resolved'], 'integrity': package['integrity']})
data = {'schema': 1, 'platform': 'linux-x86_64-glibc',
        'gnoVersion': lock['packages']['node_modules/@gmickel/gno']['version'],
        'bunVersion': lock['packages']['node_modules/@oven/bun-linux-x64-baseline']['version'],
        'artifacts': artifacts,
        'patches': json.loads((runtime.PLUGIN / 'runtime/patches.json').read_text())}
with tempfile.TemporaryDirectory(prefix='gno-recall-build-') as temp:
    root, cache = Path(temp) / 'runtime', Path(temp) / 'cache'
    root.mkdir(); cache.mkdir()
    runtime.assemble(data, root, cache, measure=True)
    data['treeSha256'] = runtime.tree_digest(root)
args.output.write_text(json.dumps(data, indent=2) + '\n')
print(f"Wrote {len(artifacts)} pinned artifacts to {args.output}")
