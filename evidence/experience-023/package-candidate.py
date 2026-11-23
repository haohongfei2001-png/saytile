"""Package the already tested signed app, without rebuilding, installation or notarization."""
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
evidence = root / "evidence/experience-023/final"
app = Path("/tmp/saytile-023-569/Saytile.app")
source = "5ebff045ff10c34dbbe12ce5235e3cef4f6d07a0"
output = Path("/Users/hhf/Documents/GitHub/saytile/dist/internal-0.23-569/Saytile-0.23-569-arm64.dmg")
identity = "92B7E50A1D43D247EA7EA19A31DCA3E407435A42"
info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
assert info["SaytileSourceRevision"] == source and info["CFBundleVersion"] == "569"
assert info["CFBundleIdentifier"] == "app.saytile.mac.mandarin-candidate"
assert not output.exists()
receipt = dict(source=source, version=info["CFBundleShortVersionString"], build=info["CFBundleVersion"],
               bundle=info["CFBundleIdentifier"], commands=[], notarization="NOT_RUN: prohibited by task")


def run(command, check=True):
    result = subprocess.run(list(map(str, command)), capture_output=True, text=True)
    receipt["commands"].append(dict(command=list(map(str, command)), exit=result.returncode,
                                    stdout=result.stdout, stderr=result.stderr))
    (evidence / "package.json").write_text(json.dumps(receipt, ensure_ascii=False, indent=2))
    if check and result.returncode:
        raise RuntimeError(f"Command failed: {command[0]}")
    return result


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


output.parent.mkdir(parents=True, exist_ok=True)
run(["codesign", "--verify", "--deep", "--strict", app])
with tempfile.TemporaryDirectory(prefix="saytile-023-package-") as temp:
    temp = Path(temp)
    volume = temp / "volume"
    volume.mkdir()
    run(["cp", "-cR", app, volume / "Saytile.app"])
    shutil.copyfile(root / "docs/delivery/experience-023/INSTALL.md", volume / "工程候选说明.txt")
    image = temp / "review.dmg"
    run(["hdiutil", "create", "-volname", "Saytile 0.23 (569)", "-srcfolder", volume, "-format", "UDZO", image])
    run(["codesign", "--force", "--timestamp", "--sign", identity, image])
    run(["codesign", "--verify", "--strict", image])
    run(["hdiutil", "verify", image])
    shutil.copyfile(image, output)
    receipt.update(dmg=str(output), bytes=output.stat().st_size, sha256=sha(output),
                   executable_sha256=sha(app / "Contents/MacOS/Saytile"),
                   worker_sha256=sha(app / "Contents/Helpers/SaytileModelWorker"))
    run(["codesign", "-dv", "--verbose=4", app])
    run(["codesign", "-dv", "--verbose=4", output])
    run(["spctl", "--assess", "--type", "execute", "--verbose=4", app], check=False)
    run(["spctl", "--assess", "--type", "open", "--context", "context:primary-signature", "--verbose=4", output], check=False)
    mount = temp / "mount"
    mount.mkdir()
    run(["hdiutil", "attach", "-readonly", "-nobrowse", "-mountpoint", mount, output])
    try:
        isolated = temp / "Applications"
        isolated.mkdir()
        copied = isolated / "Saytile.app"
        run(["ditto", mount / "Saytile.app", copied])
        assert sha(copied / "Contents/MacOS/Saytile") == receipt["executable_sha256"]
        run(["codesign", "--verify", "--deep", "--strict", copied])
        data = temp / "new-isolated-data"
        smoke = run(["sandbox-exec", "-p", "(version 1) (allow default) (deny network*)",
                     copied / "Contents/MacOS/Saytile", "--data-directory", data, "--smoke-test"])
        assert "SAYTILE_SMOKE_OK" in smoke.stdout
        receipt["isolated_offline_launch"] = "PASS"
    finally:
        run(["hdiutil", "detach", mount])
installed = Path("/Users/hhf/Applications/Saytile.app/Contents/MacOS/Saytile")
receipt["protected_533_executable_sha256"] = sha(installed)
assert receipt["protected_533_executable_sha256"] == "d711d1cab97d0ff20e23129269b8d72989db2e5258f659d49276f77cf9ab4737"
(evidence / "package.json").write_text(json.dumps(receipt, ensure_ascii=False, indent=2))
output.with_suffix(output.suffix + ".sha256").write_text(f"{receipt['sha256']}  {output.name}\n")
print(json.dumps({k:v for k,v in receipt.items() if k != "commands"}, ensure_ascii=False))
