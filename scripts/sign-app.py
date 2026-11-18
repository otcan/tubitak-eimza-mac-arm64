#!/usr/bin/env python3
"""Sign nested native code first, then frameworks and the enclosing app."""
import os
from pathlib import Path
import subprocess
import sys

app = Path(sys.argv[1]).resolve()
identity = os.environ["CODE_SIGN_IDENTITY"]
entitlements = Path(__file__).resolve().parent / "java-entitlements.plist"
magic = {bytes.fromhex(s) for s in (
    "feedface", "cefaedfe", "feedfacf", "cffaedfe", "cafebabe", "bebafeca", "cafebabf", "bfbafeca"
)}

def sign(path, java=False):
    command = ["/usr/bin/codesign", "--force", "--sign", identity,
               "--timestamp", "--options", "runtime"]
    if java:
        command += ["--entitlements", str(entitlements)]
    subprocess.run(command + [str(path)], check=True)

count = 0
for path in sorted(app.rglob("*")):
    if path.is_symlink() or not path.is_file():
        continue
    with path.open("rb") as stream:
        header = stream.read(4)
    if header not in magic:
        continue
    # Java class files share a magic number with universal Mach-O binaries.
    kind = subprocess.check_output(["/usr/bin/file", "-b", str(path)], text=True)
    if "Mach-O" not in kind:
        continue
    sign(path, path == app / "Contents/Resources/Runtime/bin/java")
    count += 1

bundles = [p for p in app.rglob("*") if p.is_dir() and not p.is_symlink()
           and p.suffix in (".framework", ".app", ".xpc", ".bundle")]
for bundle in sorted(bundles, key=lambda p: len(p.parts), reverse=True):
    sign(bundle)
sign(app)
subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)], check=True)
print(f"Signed {count} native files, {len(bundles)} nested bundles and the app.")
