"""Run the project's actual tank suites in a fresh disposable game copy."""
import argparse
from hashlib import sha256
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = next(p for p in HERE.parents if (p / "project.godot").exists())
EXPORT = HERE.parent.parent / "export" / "Bastion.glb"
SUITES = {
    "turret_aim_test": "TURRET_AIM_TEST_PASSED",
    "tank_tracks_test": "TANK_TRACKS_TEST_PASSED",
    "tank_fire_test": "TANK_FIRE_TEST_PASSED",
    "tank_death_test": "TANK_DEATH_TEST_PASSED",
    "tank_model_runtime_check": "TANK_MODEL_RUNTIME_CHECK_PASSED",
    "bastion_runtime": "BASTION_RUNTIME_PASSED",
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, type=Path)
    parser.add_argument("--baseline", action="store_true", help="Smoke-test the fixture using the accepted art")
    args = parser.parse_args()
    engine = args.godot.resolve()
    with tempfile.TemporaryDirectory(prefix="bastion_game_check_") as directory:
        tmp = Path(directory)
        project = tmp / "project"
        project.mkdir()
        for folder in ("assets", "scenes", "scripts", "tests"):
            shutil.copytree(ROOT / folder, project / folder)
        for name in ("project.godot", "icon.svg", "icon.svg.import", "Camera.tscn"):
            shutil.copy2(ROOT / name, project / name)
        if not args.baseline:
            shutil.copyfile(EXPORT, project / "assets/models/units/tank.glb")
        shutil.copyfile(HERE / "bastion_runtime.gd", project / "tests/bastion_runtime.gd")
        profile = tmp / "profile"
        output = tmp / "results"
        profile.mkdir()
        output.mkdir()
        env = dict(os.environ, APPDATA=str(profile), LOCALAPPDATA=str(profile),
                   SUPPLY_LINES_TEST_OUTPUT=str(output), BASTION_BASELINE=str(int(args.baseline)))
        game_asset = project / "assets/models/units/tank.glb"
        report = {"engine": str(engine.name), "fixture": "scenes/maps/resource_skirmish.tscn",
                  "tested_asset_sha256":sha256(game_asset.read_bytes()).hexdigest(),"suites": {}}

        def run(label, extra, marker=None):
            command = [str(engine), "--path", str(project), "--log-file", str(tmp / f"{label}.log"), *extra]
            result = subprocess.run(command, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                    timeout=180, creationflags=subprocess.CREATE_NO_WINDOW if os.name=="nt" else 0)
            stdout = result.stdout.decode("utf-8", errors="replace")
            raw_log = (tmp / f"{label}.log").read_text(encoding="utf-8", errors="replace")
            errors = [line.strip() for line in raw_log.splitlines()
                      if line.startswith(("ERROR:", "SCRIPT ERROR:")) or "Assertion failed" in line]
            if result.returncode or errors or (marker and marker not in stdout):
                raise RuntimeError(f"{label} returned {result.returncode}\n" + "\n".join(errors) + "\n" + stdout[-2400:].encode("ascii","replace").decode())
            print(f"PASS {label}", flush=True)
            return stdout

        run("import", ["--headless", "--import"])
        for name, marker in SUITES.items():
            mode = ["--headless"] if name != "tank_model_runtime_check" else [
                "--position", "-4800,-4800", "--resolution", "1280x900", "--audio-driver", "Dummy"]
            log = run(name, [*mode, "--script", f"res://tests/{name}.gd"], marker)
            report["suites"][name] = marker
            for line in log.splitlines():
                if line.startswith("TRACK_PIXELS_CHANGED "):
                    report["changed_pixels_on_track_roll"] = int(line.split()[-1])
                if line.startswith("BASTION_MEASUREMENTS "):
                    report["measurements"] = json.loads(line.partition(" ")[2])
                if line.startswith("Vulkan") or line.startswith("Direct3D"):
                    report["renderer"] = line
        if not args.baseline:
            (HERE / "runtime.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
