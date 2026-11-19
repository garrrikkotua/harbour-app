#!/usr/bin/env python3
"""Run disposable, short enforcement sessions on a test Mac (requires sudo).

Default: app-only session. --include-websites also briefly blocks example.com
and enables website firewall rules, which can reconnect network sessions.
Does not modify GUI preferences or select any of the user's real apps.
Both sessions check attempt counting; your real attempt history in
/var/db/harbour/stats-<account UUID>.json is moved aside and restored afterwards.
"""
import argparse
import json
import os
from pathlib import Path
import plistlib
import pwd
import shutil
import socket
import ssl
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parent.parent
STATE = Path('/var/db/harbour/state.json')
PLIST = Path('/Library/LaunchDaemons/com.harbour.daemon.plist')
HOSTS = Path('/etc/hosts')
PFCONF = Path('/etc/pf.conf')
ANCHOR = Path('/etc/pf.anchors/org.harbour')
TOKEN = Path('/etc/HarbourPFToken')


def account_stats_path():
    """History of the account that ran sudo (the owner recorded in
    state.json), named by its GeneratedUID like the daemon does."""
    uid = int(os.environ.get('SUDO_UID', 0))
    if uid == 0:
        return Path('/var/db/harbour/stats-unknown.json')
    name = pwd.getpwuid(uid).pw_name
    out = subprocess.run(['/usr/bin/dscl', '.', '-read', f'/Users/{name}', 'GeneratedUID'],
                         capture_output=True, text=True, timeout=10).stdout
    generated = out.split(':', 1)[-1].strip().upper()
    return Path(f'/var/db/harbour/stats-{generated}.json')


STATS = account_stats_path()
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
    """(sites, apps) counted for the session that started at `start`.

    The daemon stores sessionStart as Swift Date seconds, the same value as
    state.json's startTime, fractional part included.
    """
    try:
        stats = json.loads(STATS.read_text())
    except (OSError, ValueError):
        return {}, {}
    recorded = stats.get('sessionStart')
    if not isinstance(recorded, (int, float)) or abs(recorded - start) > 0.001:
        return {}, {}
    session = stats.get('session', {})
    return session.get('sites', {}), session.get('apps', {})


def test_user():
    """The account that ran sudo. The daemon never kills root processes, so the
    disposable app has to run as an ordinary user to be blocked at all."""
    uid, gid = int(os.environ.get('SUDO_UID', 0)), int(os.environ.get('SUDO_GID', 0))
    if uid == 0:
        raise SystemExit('Run with sudo from an ordinary account (SUDO_UID is needed).')
    return uid, gid


def launch(executable):
    uid, gid = test_user()
    return subprocess.Popen([str(executable), '60'], user=uid, group=gid, extra_groups=[])


# Attempts run in a child process as the test user: the daemon only counts
# connections opened by the block owner's account.
TLS_CLIENT = """
import socket, ssl, sys
try:
    with socket.create_connection((sys.argv[1], 443), timeout=5) as raw:
        with ssl.create_default_context().wrap_socket(raw, server_hostname=sys.argv[2]):
            sys.exit(3)  # handshake completed: the sink must reset instead
except (ssl.SSLError, OSError):
    pass  # reset or EOF during the handshake: blocked as intended
"""

HTTP_CLIENT = """
import socket, sys
with socket.create_connection((sys.argv[1], 80), timeout=5) as conn:
    conn.sendall(('GET / HTTP/1.1\\r\\nHost: %s\\r\\n\\r\\n' % sys.argv[2]).encode())
    try:
        if conn.recv(1) != b'':
            sys.exit(3)  # the sink must not serve a response
    except ConnectionError:
        pass
"""


def attempt(client, host, as_root=False):
    uid, gid = test_user()
    extra = {} if as_root else dict(user=uid, group=gid, extra_groups=[])
    result = subprocess.run([sys.executable, '-I', '-c', client, SINK, host],
                            timeout=15, **extra)
    assert result.returncode == 0, f'Sink answered {host} instead of resetting'


def tls_attempt(host, as_root=False):
    attempt(TLS_CLIENT, host, as_root)


def http_attempt(host):
    attempt(HTTP_CLIENT, host)


def reachable(address, port):
    try:
        socket.create_connection((address, port), timeout=3).close()
        return True
    except OSError:
        return False


def session(folder, websites):
    before_hosts, before_pf = HOSTS.read_text(), PFCONF.read_text()
    bundle = folder / 'Disposable.app'
    executable = bundle / 'Contents/MacOS/sleep'
    executable.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2('/bin/sleep', executable)
    # The test user must be able to reach and run the fixture.
    os.chmod(folder, 0o755)
    for path in [bundle, bundle / 'Contents', executable.parent]:
        os.chmod(path, 0o755)
    os.chmod(executable, 0o755)
    # Fractional like the app's Date(); the daemon must keep it exactly.
    now = time.time() - 978307200  # Swift Date's 2001 reference epoch.
    duration = 60 if websites else 25
    state = dict(startTime=now, endTime=now + duration, ownerUID=test_user()[0],
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
        # Already open when the block starts: closed, but not an attempt.
        child = launch(executable)
        run('/bin/launchctl', 'bootstrap', 'system', str(PLIST))
        started = True
        wait_for(lambda: child.poll() is not None, 8, 'Disposable app was not terminated')
        assert child.returncode == -9, f'Unexpected app exit: {child.returncode}'
        print('PASS: disposable app was blocked', flush=True)

        # A relaunch after the suppression window is one attempt.
        start_key = now
        time.sleep(6.5)
        assert not session_counts(start_key)[1], 'App open at block start was counted'
        child = launch(executable)
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
            # Hosts switch to the sink only once PF rejects its other ports.
            wait_for(lambda: f'{SINK}\texample.com' in HOSTS.read_text(), 20,
                     'Hosts entries do not point at the sink')
            assert f'{SINK}\tm.example.com' in HOSTS.read_text(), 'Mobile site not blocked'
            # A local service on all interfaces must stay reachable on its own
            # address (control) but not through the sink address.
            with socket.socket() as service:
                service.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                service.bind(('0.0.0.0', 0))
                service.listen(4)
                port = service.getsockname()[1]
                assert reachable('127.0.0.1', port), 'Control: local test service unreachable'
                assert not reachable(SINK, port), f'Port {port} on the sink address reached a local service'
            print('PASS: other ports on the sink address are rejected', flush=True)
            tls_attempt('www.example.com')
            tls_attempt('example.com')          # same burst: still one attempt
            tls_attempt('unrelated.example')    # not blocked: never counted
            wait_for(lambda: session_counts(start_key)[0].get('example.com') == 1, 12,
                     'TLS attempts were not counted as exactly one')
            time.sleep(10.5)                     # past the 10 s burst window
            # Another account's attempt (root here) must not reach this history.
            tls_attempt('m.example.com', as_root=True)
            time.sleep(3)
            assert session_counts(start_key)[0].get('example.com') == 1, "Another account's attempt was counted"
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
        assert STATS.stat().st_mode & 0o777 == 0o600, 'Attempt history must not be world-readable'
        assert os.stat(log).st_mode & 0o777 == 0o600, 'Daemon log must be root-only'
        assert not Path('/var/db/harbour/sink-alias').exists(), 'Sink alias ownership marker left behind'
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
    if Path('/var/db/harbour/sink-alias').exists():
        parser.error('Stale /var/db/harbour/sink-alias marker found; remove it first.')
    test_user()
    # Keep the user's real attempt history out of the test and restore it
    # after. Moving the file keeps its owner, mode and read ACL intact.
    saved_stats = STATS.with_name(STATS.name + '.smoke-backup')
    if saved_stats.exists():
        parser.error(f'{saved_stats} exists from an interrupted run; restore it to {STATS} first.')
    had_stats = STATS.exists()
    if had_stats:
        os.rename(STATS, saved_stats)
    try:
        with tempfile.TemporaryDirectory(prefix='harbour-smoke-', dir='/private/tmp') as temporary:
            folder = Path(temporary)
            session(folder, websites=False)
            if args.include_websites:
                session(folder, websites=True)
    finally:
        if had_stats:
            os.replace(saved_stats, STATS)
        else:
            STATS.unlink(missing_ok=True)
    print('Smoke tests passed. Reboot, VPN, Intel, and GUI authorization still need separate checks.')


if __name__ == '__main__':
    main()
