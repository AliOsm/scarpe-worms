#!/usr/bin/env python3
"""Compare ordinary timeouts with the package's precise animation deadline timer."""
from pathlib import Path
import argparse
import json
import subprocess

from check_package import ROOT, package_environment


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--linux-ruby', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    env, ruby = package_environment(args.app, args.linux_ruby)
    result = subprocess.run([str(ruby), '-EUTF-8', str(ROOT / 'tools/check_waits.rb'), str(args.app.resolve())],
                            env=env, check=True, stdout=subprocess.PIPE, text=True, timeout=30)
    report = json.loads(result.stdout)
    assert report['backend'] == ('TimerFD' if args.linux_ruby else 'KqueueTimer')
    report['packaged'] = True
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
