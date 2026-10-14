#!/usr/bin/env python3
"""Exercise the delivered Ruby, FFI, OpenAL Soft and CoreAudio output together."""
from pathlib import Path
import argparse
import subprocess
import sys

from check_package import package_environment


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    args = parser.parse_args()
    if sys.platform != 'darwin':
        parser.error('The delivered audio backend must be checked on macOS')
    env, ruby = package_environment(args.app, windowed=True)
    env.update(BURROW_MUTE='0', BURROW_AUDIO_EXPECT_RENDERER='OpenAL Soft',
        ALSOFT_CONF=str(args.app.resolve()/'Contents/Resources/runtime/lib/alsoftrc'),
        BURROW_OPENAL_LIBRARY=str(args.app.resolve()/'Contents/Resources/runtime/lib/libopenal.1.dylib'))
    subprocess.run([str(ruby), '-EUTF-8', str(Path(__file__).with_name('check_audio.rb'))],
                   env=env, check=True, timeout=30)


if __name__ == '__main__':
    main()
