"""Record or check the accepted tank inputs from the repository root."""
import argparse
import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = next(p for p in HERE.parents if (p / "project.godot").exists())
GLOBS = (
    "Blender/Vehicles/Tank/Tank.blend", "Blender/References/Tank.png",
    "project.godot", ".godot-version", "scenes/maps/lakes_skirmish.tscn",
    "scenes/maps/lighting.tscn", "scenes/camera/rts_camera.tscn", "scripts/camera/rts_camera.gd",
    "assets/models/units/tank*", "scenes/gameplay/tank.tscn", "scenes/gameplay/tank_shell*.tscn",
    "scenes/models/tank_model.tscn", "scenes/models/tank_death*.tscn", "scenes/models/tank_muzzle*.tscn",
    "assets/models/effects/tank_death*.glb", "assets/models/projectiles/tank*.glb",
    "assets/shaders/tank_running_gear.gdshader", "assets/materials/tank_scorch.tres",
    "assets/materials/units/team_*.tres", "assets/economy/fuel_tank.tres", "assets/units/tank.tres",
    "assets/movement/tank.tres", "scripts/gameplay/unit_agent.gd", "scripts/gameplay/projectile.gd",
    "scripts/components/tank_*.gd", "scripts/components/turret_aim.gd", "scripts/components/burst_effect.gd",
    "scripts/components/team_paint.gd", "scripts/components/visual_asset_slot.gd",
    "scripts/units/selection_bounds.gd", "scripts/units/team_colors.gd",
    "tests/tank_fire_test.gd", "tests/tank_tracks_test.gd", "tests/tank_death_test.gd",
    "tests/tank_model_runtime_check.gd",
)


def snapshot():
    files = sorted({p for pattern in GLOBS for p in ROOT.glob(pattern)})
    return {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in files}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--record", action="store_true", help="Create the initial manifest once")
    args = parser.parse_args()
    target = HERE / "accepted_inputs.json"
    current = snapshot()
    if args.record:
        with target.open("x", encoding="utf-8") as stream:
            stream.write(json.dumps(current, indent=2) + "\n")
    else:
        original = json.loads(target.read_text(encoding="utf-8"))
        changed = [p for p in sorted(current.keys() | original.keys()) if original.get(p) != current.get(p)]
        if changed:
            raise SystemExit("Changed accepted resources: " + ", ".join(changed))
    print(f"{len(current)} accepted resource hashes verified.")
