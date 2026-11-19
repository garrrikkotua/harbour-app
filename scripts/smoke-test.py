#!/usr/bin/env python3
"""Run disposable, short enforcement sessions on a test Mac (requires sudo).

Default: app-only session. --include-websites also briefly blocks example.com
and enables website firewall rules, which can reconnect network sessions.
Does not modify GUI preferences or select any of the user's real apps.
Both sessions check attempt counting; the real attempt history in
/var/db/harbour/stats.json is backed up and restored afterwards.
"""
import argparse
import json
import os
from pathlib import Path
import plistlib
import shutil
import socket
import ssl
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
STATS = Path('/var/db/harbour/stats.json')
SINK = '127.72.66.1'

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


def alias_present():
    return SINK in run('/sbin/ifconfig', 'lo0').stdout


def session_counts(start):
    """(sites, apps) counted for the session that started at `start`."""
    try:
        stats = json.loads(STATS.read_text())
    except (OSError, ValueError):
        return {}, {}
    if stats.get('sessionStart') != start:
        return {}, {}
    session = stats.get('session', {})
    return session.get('sites', {}), session.get('apps', {})


def iso(reference_seconds):
    """Swift Date (2001 epoch) seconds as the ISO 8601 string the daemon writes."""
    unix = reference_seconds + 978307200
    return time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(unix))


def tls_attempt(host):
    """Open a TLS connection to the sink as a browser would; it must be reset."""
    context = ssl.create_default_context()
    try:
        with socket.create_connection((SINK, 443), timeout=5) as raw:
            with context.wrap_socket(raw, server_hostname=host):
                raise AssertionError('Sink completed a TLS handshake; it must reset instead')
    except (ssl.SSLError, OSError):
        pass  # reset or EOF during the handshake: blocked as intended


def http_attempt(host):
    with socket.create_connection((SINK, 80), timeout=5) as conn:
        conn.sendall(f'GET / HTTP/1.1\r\nHost: {host}\r\n\r\n'.encode())
        try:
            assert conn.recv(1) == b'', 'Sink must not serve a response'
        except ConnectionError:
            pass


def session(folder, websites):
    before_hosts, before_pf = HOSTS.read_text(), PFCONF.read_text()
    bundle = folder / 'Disposable.app'
    executable = bundle / 'Contents/MacOS/sleep'
    executable.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2('/bin/sleep', executable)
    # Whole seconds so the ISO 8601 session key written by the daemon matches.
    now = float(int(time.time() - 978307200))  # Swift Date's 2001 reference epoch.
    duration = 60 if websites else 25
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

        # The first kill happens while the app was "already open" at block
        # start, so it must not count. A relaunch after that window does.
        start_key = iso(now)
        time.sleep(6.5)
        assert not session_counts(start_key)[1], 'App open at block start was counted'
        child = subprocess.Popen([str(executable), '60'])
        wait_for(lambda: child.poll() is not None, 8, 'Relaunched app was not terminated')
        wait_for(lambda: session_counts(start_key)[1].get(str(bundle)) == 1, 12,
                 'Relaunched app was not counted as one attempt')
        print('PASS: app relaunch counted once; app open at block start not counted', flush=True)

        if websites:
            wait_for(lambda: ANCHOR.exists() and 'example.com' in HOSTS.read_text(),
                     20, 'Website hosts/anchor setup did not complete')
            rules = run('/sbin/pfctl', '-a', 'org.harbour', '-sr').stdout
            assert 'block' in rules, 'No live PF blocking rules'
            print('PASS: website hosts entries and live PF rules installed', flush=True)

            assert alias_present(), f'Loopback alias {SINK} missing'
            assert f'{SINK}\texample.com' in HOSTS.read_text(), 'Hosts entries do not point at the sink'
            tls_attempt('www.example.com')
            tls_attempt('example.com')          # same burst: still one attempt
            tls_attempt('unrelated.example')    # not blocked: never counted
            wait_for(lambda: session_counts(start_key)[0].get('example.com') == 1, 12,
                     'TLS attempts were not counted as exactly one')
            time.sleep(10.5)                     # past the 10 s burst window
            http_attempt('example.com:80')
            wait_for(lambda: session_counts(start_key)[0].get('example.com') == 2, 12,
                     'HTTP attempt after the burst window was not counted')
            assert set(session_counts(start_key)[0]) == {'example.com'}, 'Unblocked host was counted'
            print('PASS: website attempts counted (TLS SNI + HTTP Host, bursts collapsed)', flush=True)
        else:
            assert HOSTS.read_text() == before_hosts and PFCONF.read_text() == before_pf
            assert not ANCHOR.exists() and not TOKEN.exists()
            print('PASS: app-only session leaves networking unchanged', flush=True)
        wait_for(cleaned, duration + 15, 'Session did not clean up automatically')
        assert 'HARBOUR_BLOCK_START' not in HOSTS.read_text()
        assert 'HARBOUR_PF_START' not in PFCONF.read_text()
        assert not ANCHOR.exists() and not TOKEN.exists()
        assert not alias_present(), f'Loopback alias {SINK} left behind'
        assert STATS.exists(), 'Attempt stats must outlive the block'
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
    if alias_present():
        parser.error(f'Loopback alias {SINK} already exists; remove it first.')
    # Keep the user's real attempt history out of the test and restore it after.
    saved_stats = STATS.read_bytes() if STATS.exists() else None
    try:
        with tempfile.TemporaryDirectory(prefix='harbour-smoke-', dir='/private/tmp') as temporary:
            folder = Path(temporary)
            session(folder, websites=False)
            if args.include_websites:
                session(folder, websites=True)
    finally:
        if saved_stats is None:
            STATS.unlink(missing_ok=True)
        else:
            STATS.write_bytes(saved_stats)
            os.chmod(STATS, 0o644)
    print('Smoke tests passed. Reboot, VPN, Intel, and GUI authorization still need separate checks.')


if __name__ == '__main__':
    main()
