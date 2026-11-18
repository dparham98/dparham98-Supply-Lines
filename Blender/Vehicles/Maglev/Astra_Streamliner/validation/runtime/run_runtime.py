"""Run the production train in an automatically discarded, independently imported game copy."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
PROTOTYPE = HERE.parent.parent
REPO = next(p for p in PROTOTYPE.parents if (p / "project.godot").is_file())
TRAIN_PATH = Path("assets/models/units/maglev_train_cargo.glb")


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(executable, stage, *arguments):
    command = [str(executable), "--headless", "--path", str(stage),
               "--log-file", str(stage.parent / "engine/run.log"), *arguments]
    profile = stage.parent / "profile"
    profile.mkdir(exist_ok=True)
    env = dict(os.environ, APPDATA=str(profile), LOCALAPPDATA=str(profile),
               XDG_DATA_HOME=str(profile), XDG_CONFIG_HOME=str(profile), XDG_CACHE_HOME=str(profile))
    result = subprocess.run(command, env=env, capture_output=True, text=True, errors="replace", timeout=480)
    output = result.stdout + result.stderr
    if result.returncode or "SCRIPT ERROR:" in output or "ERROR:" in output:
        lines = [line for line in output.splitlines() if any(tag in line for tag in
                 ["ERROR:", "FAILED:", "STREAMLINER_MEASUREMENTS=", " at:", "at: "])]
        raise RuntimeError("Godot check failed\n" + "\n".join(lines[-90:]))
    return output


def validate(executable, baseline):
    pin = (REPO / ".godot-version").read_text().strip()
    version = subprocess.check_output([executable, "--version"], text=True).strip()
    if not version.startswith(pin.replace("-", ".") + "."):
        raise ValueError(f"Project pins {pin}, executable reports {version}")
    model = (REPO / TRAIN_PATH) if baseline else PROTOTYPE / "export/maglev_train_cargo.glb"
    if not model.is_file():
        raise FileNotFoundError(model)

    with tempfile.TemporaryDirectory(prefix="SupplyLines_Streamliner_Runtime_") as folder:
        stage = Path(folder).resolve() / "project"
        if stage.is_relative_to(REPO) or not stage.is_relative_to(Path(tempfile.gettempdir()).resolve()):
            raise RuntimeError(f"Expected a fresh temporary project outside the checkout: {stage}")
        stage.mkdir()
        # A portable editor's settings, import cache, game logs and user data all stay with the test.
        binary = Path(shutil.which(str(executable)) or executable).resolve()
        engine = stage.parent / "engine"
        engine.mkdir()
        executable = shutil.copy2(binary, engine / binary.name)
        if binary.name.lower().endswith("_console.exe"):
            companion = binary.with_name(binary.name[:-len("_console.exe")] + ".exe")
            shutil.copy2(companion, engine / companion.name)
        (engine / "_sc_").touch()
        for name in ["assets", "scenes", "scripts", "tests"]:
            shutil.copytree(REPO / name, stage / name)
        for name in ["project.godot", "icon.svg", "icon.svg.import", "Camera.tscn"]:
            shutil.copy2(REPO / name, stage / name)
        # The GLB must be a fresh import at the exact path and import settings referenced by the actor.
        shutil.copy2(model, stage / TRAIN_PATH)
        shutil.copy2(HERE / "review_player.tres", stage / "assets/materials/units/team_paint_player.tres")
        shutil.copy2(HERE / "streamliner_check.gd", stage / "tests/streamliner_check.gd")
        originals = ["scripts/rails/train.gd", "scripts/rails/train_consist.gd",
                     "scripts/rails/rail_network.gd", "scripts/rails/rail_line.gd",
                     "scripts/rails/track_piece.gd", "scripts/components/team_paint.gd",
                     "scripts/gameplay/unit_agent.gd", "scripts/economy/cargo_vehicle.gd",
                     "scenes/models/train_model.tscn", "scenes/gameplay/train.tscn",
                     str(TRAIN_PATH) + ".import"]
        logic_hashes = {name: sha256(REPO / name) for name in originals}
        for name, digest in logic_hashes.items():
            if sha256(stage / name) != digest:
                raise RuntimeError(f"Reference copy mismatch: {name}")
        run(executable, stage, "--editor", "--import")
        if sha256(stage / TRAIN_PATH) != sha256(model):
            raise RuntimeError("Imported source differs from supplied GLB.")
        output = run(executable, stage, "--script", "res://tests/streamliner_check.gd")
        payload = next(line for line in output.splitlines() if line.startswith("STREAMLINER_MEASUREMENTS="))
        measurements = json.loads(payload.split("=", 1)[1])
        measurements.update({"engine": version, "glb_sha256": sha256(model),
                             "reference_script_scene_import_sha256": logic_hashes,
                             "art_palette_override": "isolated player paint only"})
        # These stock suites exercise energized fork routing and real GUI crate transfers in the same copy.
        for suite, marker in [("rail_fork_power_test", "RAIL_FORK_POWER_TEST_PASSED"),
                              ("rail_runtime_check", "RAIL_RUNTIME_CHECKS_PASSED")]:
            log = run(executable, stage, "--script", "res://tests/" + suite + ".gd")
            if marker not in log:
                raise RuntimeError(log[-6000:])
            measurements.setdefault("stock_test_markers", []).append(marker)
    return measurements


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.getenv("GODOT", "godot"), help="Path to the pinned executable")
    parser.add_argument("--baseline", action="store_true", help="Run the accepted GLB for comparison")
    args = parser.parse_args()
    data = validate(args.godot, args.baseline)
    target = HERE / ("accepted_runtime.json" if args.baseline else "prototype_runtime.json")
    target.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    print(target)
