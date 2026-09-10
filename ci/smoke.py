"""Exercise the built CLI without network or model credentials."""
from pathlib import Path
import subprocess
import tempfile

BIN = Path(__file__).resolve().parents[1] / "cairn"

def run(*args, code=0):
    p = subprocess.run([str(BIN), *map(str, args)], capture_output=True, text=True, timeout=30)
    assert p.returncode == code, (args, p.returncode, p.stdout, p.stderr)
    return p.stdout

assert "cairn solve" in run("help")
with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    (root / "main.py").write_text("def real():\n    return 1\n")
    for command, expected in [("exit 0", "baseline: exit 0"), ("exit 1", "baseline: exit 1")]:
        output = run("observe", "--root", root, "--verify", command)
        assert "main.py" in output and expected in output, output
print("CLI smoke passed: observation preserves passing and failing verification results")
