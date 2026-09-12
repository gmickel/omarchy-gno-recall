#!/usr/bin/python3
"""Check the tracked submission tree or an exported plugin directory."""
import argparse
import json
from pathlib import Path
import re
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--export', type=Path, help='Validate an exported directory instead of the Git index')
options = parser.parse_args()
root = options.export.resolve() if options.export else Path(__file__).resolve().parent.parent
if options.export:
    paths = [path.relative_to(root).as_posix() for path in root.rglob('*') if path.is_file()]
else:
    paths = subprocess.check_output(['git', 'ls-files', '-z'], cwd=root).decode().split('\0')
    paths = [path for path in paths if path]
# Match upstream scripts/build-catalog.mjs at aca841ea0d7ecc72553b1c7939549c813dad3997.
discovered = sorted(path for path in paths if re.fullmatch(r'(?:[^/]+/)?manifest\.json', path, re.IGNORECASE))
assert discovered == ['manifest.json'], f'Marketplace requires one root plugin manifest; found {discovered}'
all_manifests = sorted(path for path in paths if Path(path).name.lower() == 'manifest.json')
assert all_manifests == ['manifest.json'], f'Reserve manifest.json for the plugin: {all_manifests}'
manifest = json.loads((root / 'manifest.json').read_text())
assert manifest['schemaVersion'] == 1
for entry in manifest['entryPoints'].values():
    assert entry in paths and (root / entry).is_file(), entry
assert 'runtime/trust-manifest.json' in paths, 'Missing runtime trust manifest'
print('Marketplace layout passed: one root plugin manifest and tracked entry points.')
