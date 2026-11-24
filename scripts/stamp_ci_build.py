"""Stamp real bundle builds, not marketing versions or private feed entries."""
import os
import pathlib
import plistlib


def ci_build(run, attempt):
    run, attempt = int(run), int(attempt)
    if run < 1 or not 1 <= attempt <= 99:
        raise ValueError('invalid CI run/attempt')
    serial = run * 100 + attempt
    major, tail = divmod(serial, 10000)
    major += 2  # strictly above legacy actual 1.3.2
    if major > 9999:
        raise ValueError('CI build exhausted Apple build range')
    return f'{major}.{tail // 100}.{tail % 100}'


def stamp(root, build):
    for path in [root / 'Info.plist', *root.glob('PlugIns/**/*.appex/Info.plist')]:
        data = plistlib.loads(path.read_bytes())
        data['CFBundleVersion'] = build
        path.write_bytes(plistlib.dumps(data))


if __name__ == '__main__':
    import sys
    build = ci_build(os.environ['GITHUB_RUN_NUMBER'], os.environ.get('GITHUB_RUN_ATTEMPT', '1'))
    release_build = os.environ.get('MIRSA_RELEASE_BUILD')
    if release_build is not None:
        # Explicit metadata-only release promotion, independent of per-workflow counters.
        parts = release_build.split('.')
        if len(parts) != 3 or not all(p.isdigit() for p in parts):
            raise ValueError('invalid release build')
        if not (1 <= int(parts[0]) <= 9999 and all(0 <= int(p) <= 999 for p in parts[1:])):
            raise ValueError('release build outside bundle version limits')
        build = release_build
    stamp(pathlib.Path(sys.argv[1]), build)
    print(build)
