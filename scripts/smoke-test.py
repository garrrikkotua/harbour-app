#!/usr/bin/env python3
"""Run disposable, short enforcement sessions on a test Mac (requires sudo).

Default: app-only session. --include-websites also briefly blocks example.com
and enables website firewall rules, which can reconnect network sessions.
Does not modify GUI preferences or select any of the user's real apps.
"""
import argparse
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parent.parent
STATE = Path('/var/db/harbour/state.json')
PLIST = Path('/Library/LaunchDaemons/com.harbour.daemon.plist')
HOSTS = Path('/etc/hosts')
PFCONF = Path('/etc/pf.conf')
ANCHOR = Path('/etc/pf.anchors/org.harbour')
TOKEN = Path('/etc/HarbourPFToken')
LABEL = 'system/com.harbour.daemon'
DAEMON = ROOT / 'build/Harbour Control.app/Contents/Resources/harbour-daemon'


def run(*args, check=True):
    return subprocess.run(args, check=check, capture_output=True, text=True, timeout=15)


def wait_for(condition, seconds, message):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if condition():
            return
        time.sleep(0.25)
    raise RuntimeError(message)


def active():
    return run('/bin/launchctl', 'print', LABEL, check=False).returncode == 0


def cleaned():
    return not STATE.exists() and not PLIST.exists() and not active()


def session(folder, websites):
    before_hosts, before_pf = HOSTS.read_text(), PFCONF.read_text()
    bundle = folder / 'Disposable.app'
    executable = bundle / 'Contents/MacOS/sleep'
    executable.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2('/bin/sleep', executable)
    now = time.time() - 978307200  # Swift Date's 2001 reference epoch.
    duration = 35 if websites else 12
    state = dict(startTime=now, endTime=now + duration,
                 domains=['example.com'] if websites else [],
                 blockedPaths=[str(bundle)], blockedBundleIDs=['test.harbour.disposable'])
    STATE.parent.mkdir(parents=True, exist_ok=True)
    STATE.write_text(json.dumps(state))
    os.chmod(STATE, 0o644)
    log = folder / 'daemon.log'
    PLIST.write_bytes(plistlib.dumps(dict(Label='com.harbour.daemon',
        ProgramArguments=[str(DAEMON)], RunAtLoad=True,
        KeepAlive={'SuccessfulExit': False}, ThrottleInterval=1,
        StandardOutPath=str(log), StandardErrorPath=str(log))))
    os.chmod(PLIST, 0o644)
    started = False
    child = None
    try:
        run('/bin/launchctl', 'bootstrap', 'system', str(PLIST))
        started = True
        child = subprocess.Popen([str(executable), '60'])
        wait_for(lambda: child.poll() is not None, 8, 'Disposable app was not terminated')
        assert child.returncode == -9, f'Unexpected app exit: {child.returncode}'
        print('PASS: disposable app was blocked', flush=True)
        if websites:
            wait_for(lambda: ANCHOR.exists() and 'example.com' in HOSTS.read_text(),
                     20, 'Website hosts/anchor setup did not complete')
            rules = run('/sbin/pfctl', '-a', 'org.harbour', '-sr').stdout
            assert 'block' in rules, 'No live PF blocking rules'
            print('PASS: website hosts entries and live PF rules installed', flush=True)
        else:
            assert HOSTS.read_text() == before_hosts and PFCONF.read_text() == before_pf
            assert not ANCHOR.exists() and not TOKEN.exists()
            print('PASS: app-only session leaves networking unchanged', flush=True)
        wait_for(cleaned, duration + 15, 'Session did not clean up automatically')
        assert 'HARBOUR_BLOCK_START' not in HOSTS.read_text()
        assert 'HARBOUR_PF_START' not in PFCONF.read_text()
        assert not ANCHOR.exists() and not TOKEN.exists()
        # Compare nonempty lines because the existing marker stripper normalizes
        # whitespace around its own appended section.
        lines = lambda text: [line for line in text.splitlines() if line.strip()]
        assert lines(HOSTS.read_text()) == lines(before_hosts), 'Unrelated hosts entries changed'
        assert lines(PFCONF.read_text()) == lines(before_pf), 'Unrelated PF configuration changed'
        print('PASS: timer expired and state, job, hosts, and firewall entries cleaned up', flush=True)
    finally:
        if child and child.poll() is None:
            child.terminate()
            child.wait(timeout=5)
        # Use the daemon's own cleanup; never overwrite system network files.
        if active():
            run('/bin/launchctl', 'bootout', LABEL, check=False)
        if STATE.exists():
            if started:
                wait_for(lambda: not STATE.exists(), 15, f'Cleanup incomplete; inspect {log}')
            else:
                STATE.unlink(missing_ok=True)
                PLIST.unlink(missing_ok=True)
        if log.exists():
            destination = ROOT / 'build' / ('smoke-websites.log' if websites else 'smoke-apps.log')
            shutil.copy2(log, destination)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--include-websites', action='store_true')
    args = parser.parse_args()
    if os.geteuid() != 0:
        parser.error('Run with sudo on a test Mac.')
    if not DAEMON.is_file():
        parser.error('Build the app with ./build.sh first.')
    if active() or any(p.exists() for p in [STATE, PLIST, ANCHOR, TOKEN]):
        parser.error('Existing Harbour installation/state found; wait for normal cleanup first.')
    if 'HARBOUR' in HOSTS.read_text() or 'HARBOUR' in PFCONF.read_text():
        parser.error('Existing Harbour network markers found; resolve them first.')
    with tempfile.TemporaryDirectory(prefix='harbour-smoke-', dir='/private/tmp') as temporary:
        folder = Path(temporary)
        session(folder, websites=False)
        if args.include_websites:
            session(folder, websites=True)
    print('Smoke tests passed. Reboot, VPN, Intel, and GUI authorization still need separate checks.')


if __name__ == '__main__':
    main()
