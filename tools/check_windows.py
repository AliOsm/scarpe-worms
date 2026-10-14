#!/usr/bin/env python3
"""Exercise delivered Windows binaries on a disposable GitHub runner.

Installs in a Unicode/space path, runs a windowed bot match, resumes its save,
upgrades/uninstalls, then exercises the independently extracted portable ZIP.
No installed Ruby, Rust, Bundler or other developer executable is on app PATH.
"""
from pathlib import Path
import ctypes
from ctypes import wintypes
import hashlib
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / '.cache/windows'
OUTPUT = CACHE / 'evidence'
WORK = CACHE / 'Verification Zoë Q 雪'
REGISTRY = r'Software\Microsoft\Windows\CurrentVersion\Uninstall\{DBF988C5-81A8-4D96-8386-A391044EF965}_is1'


def read_json(path):
    return json.loads(path.read_text(encoding='utf-8'))


def digest(path):
    with path.open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()


def summary(values):
    values = sorted(values)
    return {'samples': len(values), 'mean_ms': sum(values) / len(values),
            'p95_ms': values[int(len(values) * 0.95)], 'max_ms': values[-1]} if values else {}


def run(*args, **options):
    return subprocess.run([str(a) for a in args], check=True, timeout=180, **options)


def report_text(value):
    """Keep diagnostics UTF-8 even when the runner's console is cp1252."""
    data = value if isinstance(value, bytes) else str(value).encode('utf-8', 'replace')
    sys.stdout.buffer.write(data)
    if not data.endswith(b'\n'):
        sys.stdout.buffer.write(b'\n')
    sys.stdout.buffer.flush()


def verify_files(bundle):
    manifest = read_json(bundle / 'resources/files.sha256.json')
    for name, expected in manifest.items():
        if digest(bundle / name) != expected:
            raise RuntimeError(f'Packaged file mismatch: {name}')


def no_orphans(pids):
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
    kernel.OpenProcess.restype = wintypes.HANDLE
    kernel.WaitForSingleObject.argtypes = [wintypes.HANDLE, wintypes.DWORD]
    kernel.CloseHandle.argtypes = [wintypes.HANDLE]
    for pid in pids:
        handle = kernel.OpenProcess(0x100000, False, pid)  # SYNCHRONIZE
        if handle:
            try:
                if kernel.WaitForSingleObject(handle, 3000) != 0:
                    raise RuntimeError(f'Child process survived quit: {pid}')
            finally:
                kernel.CloseHandle(handle)
        elif ctypes.get_last_error() != 87:  # ERROR_INVALID_PARAMETER = no such PID
            raise ctypes.WinError(ctypes.get_last_error())


def environment(profile, output, headless):
    local = profile / 'AppData/Local'
    temporary = profile / 'Temporary Équipe'
    local.mkdir(parents=True, exist_ok=True)
    temporary.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    for key in list(env):
        if key.startswith(('BURROW_', 'SCARPE_', 'BUNDLE_', 'GEM_')) or key in ('RUBYLIB', 'RUBYOPT', 'BUNDLER_SETUP'):
            env.pop(key)
    system_root = env.get('SystemRoot') or env.get('SYSTEMROOT') or r'C:\Windows'
    env.update({
        'LOCALAPPDATA': str(local), 'TMPDIR': str(temporary), 'TEMP': str(temporary), 'TMP': str(temporary),
        'SCARPE_NATIVE_HEADLESS': '1' if headless else '0', 'ALSOFT_DRIVERS': 'null',
        'BURROW_WINDOWS_PROBE': str(ROOT / 'packaging/windows/smoke.rb'),
        'BURROW_WINDOWS_REPORT': str(output / 'result.json'),
        'BURROW_SMOKE_SHOT': str(output / 'battle.png'),
        'PATH': os.pathsep.join([str(Path(system_root) / 'System32'), system_root]),
        # The launcher must replace inherited developer Ruby configuration.
        'RUBYLIB': 'C:/missing-ruby-libraries', 'RUBYOPT': '-rmissing-burrow-test-library',
        'GEM_HOME': 'C:/missing-gems', 'GEM_PATH': 'C:/missing-gems',
        'BUNDLE_GEMFILE': 'C:/missing-Gemfile',
    })
    return env, local / 'burrow-brigade', local / 'Burrow Brigade/Logs'


def play(bundle, profile, label, *, headless=False):
    output = OUTPUT / label
    output.mkdir(parents=True, exist_ok=True)
    env, data, logs = environment(profile, output, headless)
    launches = []
    for resume in ('0', '1'):
        env['BURROW_SMOKE_RESUME'] = resume
        process = subprocess.Popen([str(bundle / 'Burrow Brigade.exe')], cwd=WORK, env=env,
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        try:
            console, _ = process.communicate(timeout=150)
        except subprocess.TimeoutExpired:
            subprocess.run(['taskkill.exe', '/PID', str(process.pid), '/T', '/F'], check=False)
            raise
        finally:
            if logs.exists():
                shutil.copytree(logs, output / f'logs-{resume}', dirs_exist_ok=True)
        if process.returncode:
            report_text(console.decode('utf-8', errors='replace'))
            if (logs / 'launcher.log').exists():
                report_text((logs / 'launcher.log').read_text(encoding='utf-8', errors='replace'))
            raise RuntimeError(f'{label} launch {resume} exited with {process.returncode}')
        report = read_json(output / 'result.json')
        assert report['external_encoding'] == 'UTF-8'
        assert Path(report['bundled_interpreter']).is_relative_to(bundle)
        no_orphans([process.pid, *report['child_pids']])
        assert not any((profile / 'Temporary Équipe').glob('burrow-terrain-*')), 'Terrain scratch was not removed'
        assert (data / 'preferences.json').is_file(), 'Missing saved preferences'
        saves = list(data.glob('**/server.json'))
        assert saves and any(read_json(save)['rooms'] for save in saves), 'Missing saved match'
        launches.append(report)
    assert launches[0]['match_id'] == launches[1]['match_id'], 'Resume replaced the match'
    assert launches[0]['player_id'] == launches[1]['player_id'], 'Resume replaced the player'
    assert launches[0]['fired_shot_visible'], 'No native presentation of the shot'
    sessions = sorted((logs / 'performance').glob('session-*'))
    assert len(sessions) == 2, 'Default Windows diagnostics path was not used'
    timings = []
    for session in sessions:
        timing = {}
        for name in ('session.json', 'ruby.json', 'rust.json', 'game.json', 'audio.json'):
            value = read_json(session / name)
            if name in ('rust.json', 'game.json'):
                assert value['frames'] and len(value['frames']) <= value['sample_limit'] == 10000
            elif name == 'ruby.json':
                assert value['wait_samples'], 'Scheduler did not record wakeups'
                assert len(value['wait_samples']) <= value['wait_sample_limit'] == 10000
                timing['wait_backend'] = value['wait_backend']
                timing['wait_overshoot'] = summary([row[3] for row in value['wait_samples'] if 0 < row[1] <= 100])
            if name == 'game.json':
                interval = value['columns'].index('interval_ms')
                page = value['columns'].index('page')
                timing['match_update_intervals'] = summary([row[interval] for row in value['frames'] if row[page] == 'match' and row[interval] is not None])
        timings.append(timing)
    verify_files(bundle)  # Read-only application: no packaged source/assets changed.
    result = {'passed': True, 'launches': launches, 'saved_match_resumed': True,
              'no_orphan_processes': True, 'no_developer_tools_on_path': True,
              'default_windows_data_and_logs': True, 'bounded_diagnostics': True,
              'timing_diagnostics_not_release_gates': timings}
    (output / 'passed.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    return result, data


def state_hashes(data):
    return {p.relative_to(data).as_posix(): digest(p) for p in data.rglob('*') if p.is_file()}


def main():
    if sys.platform != 'win32' or os.environ.get('GITHUB_ACTIONS') != 'true':
        raise SystemExit('Run installer verification on a disposable GitHub Windows runner.')
    import winreg
    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, REGISTRY):
            raise RuntimeError('Refusing to replace an existing Burrow Brigade installation')
    except FileNotFoundError:
        pass
    build = read_json(OUTPUT / 'build.json')
    for asset in build['assets']:
        path = ROOT / 'dist' / asset['name']
        assert digest(path) == asset['sha256']
        assert Path(str(path) + '.sha256').read_text().strip() == f"{asset['sha256']}  {path.name}"
    if WORK.exists():
        shutil.rmtree(WORK)
    WORK.mkdir(parents=True)
    bundle = WORK / 'Installed Burrow Équipe برج'
    version = build['version']
    installer = ROOT / 'dist' / f'Burrow-Brigade-{version}-windows-x64-setup.exe'
    arguments = ['/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-', f'/DIR={bundle}', '/TASKS=desktopicon']
    run(installer, *arguments, f'/LOG={OUTPUT / "install.log"}')
    shortcut = Path(os.environ['APPDATA']) / 'Microsoft/Windows/Start Menu/Programs/Burrow Brigade.lnk'
    assert shortcut.exists(), 'Missing Start menu shortcut'
    with winreg.OpenKey(winreg.HKEY_CURRENT_USER, REGISTRY) as key:
        assert winreg.QueryValueEx(key, 'DisplayName')[0] == 'Burrow Brigade'
        assert Path(winreg.QueryValueEx(key, 'InstallLocation')[0]) == bundle
    installed, data = play(bundle, WORK / 'Installed profile Zoë Q', 'installed')
    before = state_hashes(data)
    (bundle / 'resources/obsolete-test.txt').write_text('old version resource')
    run(installer, *arguments, f'/LOG={OUTPUT / "upgrade.log"}')
    assert not (bundle / 'resources/obsolete-test.txt').exists(), 'Upgrade retained obsolete resources'
    assert state_hashes(data) == before, 'Upgrade changed saved state'
    verify_files(bundle)
    run(bundle / 'unins000.exe', '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', f'/LOG={OUTPUT / "uninstall.log"}')
    assert not (bundle / 'Burrow Brigade.exe').exists() and not (bundle / 'resources').exists()
    assert not shortcut.exists(), 'Uninstall retained shortcut'
    assert state_hashes(data) == before, 'Uninstall changed saved state'
    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, REGISTRY):
            raise RuntimeError('Uninstall retained application registry entry')
    except FileNotFoundError:
        pass
    spec = importlib.util.spec_from_file_location('package_windows', ROOT / 'tools/package_windows.py')
    packaging = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(packaging)
    portable = WORK / 'Portable Équipe'
    packaging.extract_zip(ROOT / 'dist' / f'Burrow-Brigade-{version}-windows-x64.zip', portable)
    portable_result, _ = play(portable / 'Burrow Brigade', WORK / 'Portable profile Zoë Q', 'portable', headless=True)
    report = {'passed': True, 'build': build, 'installed': installed, 'portable': portable_result,
              'checks': ['silent_per_user_install', 'unicode_installation_and_data_paths', 'start_menu_shortcut',
                         'installed_app_registry', 'windowed_native_match', 'openal_soft_null_mixer',
                         'save_and_resume', 'no_orphans', 'upgrade_removes_obsolete_resources',
                         'uninstall', 'preserved_saves', 'portable_extracted_zip', 'asset_checksums']}
    (OUTPUT / 'passed.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'passed': True, 'checks': report['checks'], 'assets': build['assets']}, indent=2))


if __name__ == '__main__':
    main()
