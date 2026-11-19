"""Exercise the opt-in actor in a fresh game copy with the project's pinned Godot."""
import argparse
from hashlib import sha256
import json
import os
from pathlib import Path
import runpy
import shutil
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
PACKAGE = HERE.parent
ROOT = next(parent for parent in PACKAGE.parents if (parent / ".godot-version").is_file())
EXPORT = PACKAGE / "export/Bastion_AutoTurret.glb"


def invoke(engine, project, profile, label, flags):
    log = profile / (label + ".log")
    environment = dict(os.environ, APPDATA=str(profile), LOCALAPPDATA=str(profile),
                       SUPPLY_LINES_TEST_OUTPUT=str(profile / "results"))
    command = [str(engine), "--headless", "--path", str(project), "--log-file", str(log), *flags]
    proc = subprocess.run(command, env=environment, capture_output=True, timeout=180,
                          creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
    output = log.read_text(encoding="utf-8") if log.exists() else proc.stdout.decode(errors="replace")
    errors = [line for line in output.splitlines()
              if line.startswith(("ERROR:", "SCRIPT ERROR:")) or "Assertion failed" in line]
    if proc.returncode or errors:
        raise RuntimeError(f"{label} exited {proc.returncode}\n" + "\n".join(errors) + "\n" + output[-1900:])
    return output


def main(engine):
    artifact = {
        "asset_sha256": sha256(EXPORT.read_bytes()).hexdigest(),
        "controller_sha256": sha256((PACKAGE / "gameplay/close_defense.gd").read_bytes()).hexdigest(),
        "bullet_scene_sha256": sha256((PACKAGE / "gameplay/aux_bullet.tscn").read_bytes()).hexdigest(),
        "bullet_script_sha256": sha256((PACKAGE / "gameplay/aux_bullet.gd").read_bytes()).hexdigest(),
        "map": "res://scenes/maps/resource_skirmish.tscn",
        "actor": "res://bastion/bastion_tank.tscn",
        "fixed_frames_per_second": 60,
        "primary_regressions": {},
    }
    with tempfile.TemporaryDirectory(prefix="bastion_cupola_check_") as temp:
        project = Path(temp) / "game"
        profile = Path(temp) / "profile"
        project.mkdir()
        profile.mkdir()
        for directory in ("assets", "scripts", "scenes", "tests"):
            shutil.copytree(ROOT / directory, project / directory)
        for filename in ("project.godot", "icon.svg", "icon.svg.import", "Camera.tscn"):
            shutil.copy2(ROOT / filename, project / filename)
        stage = runpy.run_path(str(PACKAGE / "gameplay/stage_actor.py"))["stage"]
        stage(project)
        shutil.copyfile(HERE / "combat_test.gd", project / "tests/bastion_cupola_test.gd")
        # The stock fire, death and track suites instantiate the stock scene by path.
        # Put the same new mesh in its stock model slot within this throwaway game.
        shutil.copyfile(EXPORT, project / "assets/models/units/tank.glb")
        invoke(engine, project, profile, "import", ["--import"])
        cases = {
            "bastion_cupola_test": "CUPOLA_COMBAT_PASSED",
            "tank_fire_test": "TANK_FIRE_TEST_PASSED",
            "tank_tracks_test": "TANK_TRACKS_TEST_PASSED",
            "tank_death_test": "TANK_DEATH_TEST_PASSED",
        }
        for case, marker in cases.items():
            output = invoke(engine, project, profile, case,
                            ["--fixed-fps", "60", "--script", f"res://tests/{case}.gd"])
            if marker not in output:
                raise RuntimeError(f"{case} did not finish\n" + output[-1600:])
            if case == "bastion_cupola_test":
                line = next(line for line in output.splitlines() if line.startswith("CUPOLA_MEASUREMENTS "))
                artifact["secondary_combat"] = json.loads(line.partition(" ")[2])
                artifact["engine"] = next(line for line in output.splitlines() if "Godot Engine v" in line)
            else:
                artifact["primary_regressions"][case] = marker
            print(marker, flush=True)
    (HERE / "combat.json").write_text(json.dumps(artifact, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    main(parser.parse_args().godot.resolve())
