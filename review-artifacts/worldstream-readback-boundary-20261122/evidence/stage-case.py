"""Stage a disclosed synthetic case for the existing launcher. No model or service calls."""
from pathlib import Path
import argparse
import json
import hashlib
import os
import shutil
import subprocess

here = Path(__file__).resolve().parent
seal = json.loads((here / 'sealed.json').read_text())
parser = argparse.ArgumentParser()
parser.add_argument('variant', choices=seal['order'])
parser.add_argument('new_case', type=Path)
args = parser.parse_args()
case = args.new_case.resolve()
case.mkdir(mode=0o700, exist_ok=False)
for name, digest in seal['inputs'][args.variant].items():
    src = here / 'inputs' / args.variant / name
    assert hashlib.sha256(src.read_bytes()).hexdigest() == digest
    shutil.copyfile(src, case / name)
common = here / 'inputs' / 'common'
for name in ('parcel.bundle', 'offer.json'):
    shutil.copyfile(common / name, case / name)
env = dict(PATH='/usr/bin:/bin', HOME=str(case), LC_ALL='C',
           GIT_CONFIG_NOSYSTEM='1', GIT_ALLOW_PROTOCOL='file', GIT_TERMINAL_PROMPT='0')
def git(*args):
    subprocess.run(['/usr/bin/git', *args], cwd=case, env=env, check=True)
git('init', '--quiet', '--bare', '--template=', '-b', 'main', 'base.git')
git('--git-dir=base.git', 'fetch', '--quiet', '--no-tags', '--no-write-fetch-head',
    str(common / 'base.bundle'), 'refs/heads/main:refs/heads/main')
for name in ('offer.json', 'readback.json', 'checkpoint.txt', 'parcel.bundle'):
    os.chmod(case / name, 0o444)
