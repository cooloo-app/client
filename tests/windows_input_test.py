"""Windows native console gate; pass a GUI-subsystem console_input_probe.exe."""
import ctypes
import os
from pathlib import Path
import subprocess
import sys

exe = str(Path(sys.argv[1]).resolve())
kernel = ctypes.WinDLL("kernel32", use_last_error=True)
allocated = bool(kernel.AllocConsole())
try:
    env = dict(os.environ)
    env.pop("COOLOO_LAUNCHER_WAIT", None)
    with open("CONIN$", "r") as console:
        for waiting in (False, True):
            child_env = dict(env)
            if waiting:
                child_env["COOLOO_LAUNCHER_WAIT"] = "1"
            result = subprocess.run([exe], stdin=console, capture_output=True,
                                    text=True, env=child_env, timeout=10)
            assert result.returncode == 0, result
            assert result.stdout.strip() == f"terminal=1 readable={int(waiting)}", result
            assert ("Python launcher" in result.stderr) == (not waiting), result
    result = subprocess.run([exe], input="y\n", capture_output=True,
                            text=True, env=dict(env, COOLOO_LAUNCHER_WAIT="1"), timeout=10)
    assert result.returncode == 0 and result.stdout.strip() == "terminal=0 readable=0", result
finally:
    if allocated:
        kernel.FreeConsole()
print("PASS: GUI native console reads require waiting launcher; redirected input cannot consent")
