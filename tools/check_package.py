#!/usr/bin/env python3
"""Run bundled game/boot code on a Mac, or explicitly substitute Linux executables."""
from pathlib import Path
import argparse
import json
import os
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def package_environment(app, linux_ruby=None, windowed=False):
    res = app.resolve() / 'Contents/Resources'
    if sys.platform != 'darwin' and not linux_ruby:
        raise ValueError('Mac binaries need macOS. --linux-ruby only checks relocated Ruby code with Linux executables.')
    env = os.environ.copy()
    for key in ['RUBYOPT', 'RUBYLIB', 'GEM_HOME', 'GEM_PATH', 'BUNDLE_GEMFILE', 'BUNDLE_PATH',
                'BUNDLE_BIN_PATH', 'DYLD_LIBRARY_PATH', 'BURROW_CONNECT', 'BURROW_AUTOPLAY']:
        env.pop(key, None)
    paths = [res / 'scarpe' / p for p in ['lib', 'lacci/lib', 'scarpe-components/lib']]
    paths.extend(res / 'gems' / name / 'lib' for name in ['ffi', 'chunky_png', 'base64', 'logger', 'fastimage'])
    ruby = linux_ruby.resolve() if linux_ruby else res / 'runtime/ruby/bin.real/ruby'
    if linux_ruby:
        abi = subprocess.check_output([str(ruby), '--disable-gems', '-e', "print RUBY_VERSION.split('.')[0,2].join('.')"], text=True)
        # Keep the delivered ffi Ruby code; only substitute its platform binary,
        # just as this mode explicitly substitutes Ruby and scarpe-native.
        extensions = sorted((ROOT/'vendor/bundle/ruby').glob(f'*/gems/ffi-1.17.4-*-linux*/lib/{abi}/ffi_c.so'))
        if extensions:
            paths.append(extensions[0].parent)
            env['BURROW_TEST_FFI_EXTENSION'] = str(extensions[0])
    if not linux_ruby:
        base = res / 'runtime/ruby/lib/ruby'
        paths.extend(base / p for p in ['site_ruby/3.4.0', 'site_ruby/3.4.0/arm64-darwin22', 'site_ruby',
                     'vendor_ruby/3.4.0', 'vendor_ruby/3.4.0/arm64-darwin22', 'vendor_ruby',
                     '3.4.0', '3.4.0/arm64-darwin22'])
        env['RUBYOPT'] = '-rtraveling_ruby_restore_environment'
    native = ROOT / 'vendor/scarpe/native/target/release/scarpe-native' if linux_ruby else res.parent / 'MacOS/scarpe-native'
    env.update(RUBYLIB=os.pathsep.join(map(str, paths)), GEM_HOME=str(res / 'runtime/gems'),
               GEM_PATH=str(res / 'runtime/gems'), SCARPE_DISPLAY_SERVICE='native',
               SCARPE_NATIVE_BIN=str(native), SCARPE_NATIVE_HEADLESS='0' if windowed else '1',
               BURROW_PACKAGE_RES=str(res), BURROW_RUBY=str(ruby))
    return env, ruby


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    parser.add_argument('--linux-ruby', type=Path, help='Ruby 3.4 on Linux; this does NOT test Mac binaries')
    parser.add_argument('--windowed', action='store_true', help='Open the actual native window on a Mac')
    parser.add_argument('--locale', choices=['unset', 'c', 'inherit'], default='unset',
                        help='Default: remove shell locale variables as on a Finder launch; c forces ASCII')
    args = parser.parse_args()
    try:
        env, ruby = package_environment(args.app, args.linux_ruby, args.windowed)
    except ValueError as error:
        parser.error(str(error))
    output = ROOT / 'docs/validation'
    output.mkdir(parents=True, exist_ok=True)
    suffix = 'relocated-linux' if args.linux_ruby else 'macos-native'
    suffix += '-windowed' if args.windowed else ''
    suffix += '-locale-c' if args.locale == 'c' else ''
    if args.locale != 'inherit':
        for key in list(env):
            if key.startswith('LC_') or key in ('LANG', 'LANGUAGE'):
                del env[key]
        if args.locale == 'c':
            env.update(LC_ALL='C', LANG='C')
    # U+00A0 starts with the C2 byte from the reported Mac startup failure.
    with tempfile.TemporaryDirectory(prefix='Burrow\u00a0Jos\u00e9 smoke ') as data:
        temporary = Path(data) / 'temporary terrain'
        temporary.mkdir()
        env.pop('SCARPE_NATIVE_STATS', None)
        env.update(BURROW_MUTE='1', BURROW_DATA_DIR=data, BURROW_LOG_DIR=str(Path(data)/'logs'),
                   TMPDIR=str(temporary),
                   BURROW_SMOKE_REPORT=str(output / f'package-{suffix}.json'),
                   BURROW_SMOKE_SHOT=str(output / f'package-{suffix}.png'))
        report_path = output / f'package-{suffix}.json'
        launches = []
        for resume in ('0', '1'):
            env['BURROW_SMOKE_RESUME'] = resume
            # Match launch.sh's interpreter options, including its explicit
            # encoding. The host and terrain workers independently exec Ruby.
            subprocess.run([str(ruby), '-EUTF-8', str(ROOT / 'tools/package_smoke.rb')],
                           cwd=data, env=env, check=True, timeout=45)
            launches.append(json.loads(report_path.read_text(encoding='utf-8')))
        assert launches[0]['match_id'] == launches[1]['match_id'], 'Restart created a new match'
        assert launches[0]['player_id'] == launches[1]['player_id'], 'Restart replaced the player'
        assert all(run['unicode_terrain_path'] for run in launches), 'Terrain did not exercise Unicode paths'
        sessions = list((Path(data)/'logs/performance').glob('session-*'))
        assert len(sessions) == 2, 'Packaged diagnostics were not initialized for both launches'
        for session in sessions:
            for name in ('session.json', 'ruby.json', 'rust.json', 'game.json'):
                log = json.loads((session/name).read_text(encoding='utf-8'))
                if name in ('rust.json', 'game.json'):
                    assert log['sample_policy'] == 'most_recent'
                    assert len(log['frames']) <= log['sample_limit'] == 10000
                    assert log['frames'], f'Empty {name} timeline'
                    if name == 'rust.json' and args.windowed:
                        assert log['counters']['exit_callback_flush'] == 1, 'Native exit callback did not save timings'
                elif name == 'ruby.json':
                    assert log['wait_samples'], 'Missing scheduler wake-up samples'
                    assert len(log['wait_samples']) <= log['wait_sample_limit'] == 10000
                    assert log['wait_backend']['name'] == ('TimerFD' if args.linux_ruby else 'KqueueTimer'), 'Precise deadline timer did not initialize'
                    assert log['wait_backend']['error'] is None, 'Precise deadline timer failed during play'
        report = launches[-1]
        report.update(bounded_local_diagnostics=True, launch_locale=args.locale, launches=2,
                      unicode_data_path=True, recovered_same_match=True, restored_same_player=True)
        report_path.write_text(json.dumps(report, indent=2)+'\n')


if __name__ == '__main__':
    main()
