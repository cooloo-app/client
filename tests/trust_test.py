"""Isolated TOFU regressions: terminal consent must not consume payload stdin."""
import os
from pathlib import Path
import pty
import select
import socket
import subprocess
import tempfile
import time

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="cooloo-trust-") as tmp:
    base = Path(tmp)
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        port = s.getsockname()[1]
    env = dict(os.environ, COOLOO_HOME=str(base / "server"),
               COOLOO_CONFIG=str(base / "client"), COOLOO_HOST=f"127.0.0.1:{port}")
    cli = str(root / "cooloo-cli")
    daemon = subprocess.Popen([str(root.parent / "server/coolood"), "-b", "127.0.0.1", "-p", str(port)],
                              env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    pin = base / "client/known_servers"
    def run(*args, input=""):
        return subprocess.run([cli, *args], env=env, input=input, text=True,
                              capture_output=True, timeout=5)
    def terminal(answer):
        master, slave = pty.openpty()
        proc = subprocess.Popen([cli, "rooms"], env=env, stdin=slave, stdout=slave, stderr=slave)
        os.close(slave)
        try:
            output = b""
            deadline = time.monotonic() + 5
            while b"[y/N]" not in output:
                assert time.monotonic() < deadline, output
                if select.select([master], [], [], .1)[0]:
                    output += os.read(master, 4096)
            os.write(master, answer)
            assert proc.wait(timeout=5) == 1  # unregistered or refused
        finally:
            if proc.poll() is None:
                proc.kill()
                proc.wait()
            os.close(master)
    try:
        for _ in range(100):
            try:
                with socket.create_connection(("127.0.0.1", port), timeout=.1):
                    break
            except OSError:
                assert daemon.poll() is None
                time.sleep(.02)
        else:
            raise AssertionError("daemon not ready")
        assert run("keygen").returncode == 0
        for payload in ("", "y\n", "yes\n", "yesterday\n"):
            result = run("rooms", input=payload)
            assert result.returncode == 1 and "[y/N]" not in result.stderr, result
            assert not pin.exists()
        for answer in (b"n\n", b"\x04", b"yesterday\n", b"y" * 40 + b"\n"):
            terminal(answer)
            assert not pin.exists()
        for answer in (b"y\n", b"Y\n", b"yes\n"):
            terminal(answer)
            assert pin.exists()
            pin.unlink()
        result = run("-y", "whoami", "--register", "trust-test")
        assert result.returncode == 0, result
        room = run("create", "trust-room").stdout.split()[1]
        payload = "yesterday\nsecond line\n"
        assert run("send", room, input=payload).returncode == 0
        assert "yesterday" in run("read", "--raw", room, "0").stdout
        original = pin.read_text()
        fields = original.split()
        fields[1] = ("0" if fields[1][0] != "0" else "1") + fields[1][1:]
        pin.write_text(" ".join(fields) + "\n")
        changed = pin.read_bytes()
        result = run("-y", "rooms", input="y\n")
        assert result.returncode == 1 and "[y/N]" not in result.stderr
        assert pin.read_bytes() == changed
    finally:
        daemon.terminate()
        daemon.wait(timeout=5)
print("PASS: terminal consent, denial/EOF, noninteractive input, pinned sends and changed-pin rejection")
