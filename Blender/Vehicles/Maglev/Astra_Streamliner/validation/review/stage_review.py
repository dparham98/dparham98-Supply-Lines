"""Stage a self-contained Godot visual review outside the game's resource tree."""
import argparse
from pathlib import Path
import shutil
import zipfile

HERE = Path(__file__).resolve().parent
PROTOTYPE = HERE.parent.parent
GAME = PROTOTYPE.parents[3]


def stage(destination, model):
    destination = destination.resolve()
    if destination == GAME or GAME in destination.parents:
        raise SystemExit("Choose a review destination outside the game project.")
    marker = destination / ".streamliner-review"
    if destination.is_dir() and any(destination.iterdir()) and not marker.is_file():
        raise SystemExit("Choose an empty review directory or reuse a staged review.")
    destination.mkdir(parents=True, exist_ok=True)
    marker.touch()
    resources = [
        (HERE / name, name)
        for name in ["project.godot", "review.tscn", "review.gd", "rail_strip.tscn",
                     "yard_extensions.tscn", "grass_stage.tres", "floor.gdshader"]
    ]
    resources += [
        (GAME / relative, relative)
        for relative in [
            "scripts/components/team_paint.gd",
            "assets/materials/units/team_paint_enemy.tres",
            "assets/materials/units/team_paint_neutral.tres",
            "assets/models/units/maglev_train_cargo.glb",
            "assets/models/units/cargo_truck.glb",
            "assets/models/rails/maglev_track_straight.glb",
            "assets/shaders/terrain_surface.gdshader",
        ]
    ]
    for texture in ["assets/textures/terrain/ground_tiles_albedo.png",
                    "assets/textures/terrain/ground_tiles_normal.png"]:
        for suffix in ["", ".import"]:
            resources.append((GAME / (texture + suffix), texture + suffix))
    resources += [
        (GAME / "scenes/maps/lighting.tscn", "lighting.tscn"),
        (HERE.parent / "runtime/review_player.tres", "assets/materials/units/team_paint_player.tres"),
        (model, "assets/models/units/streamliner.glb"),
    ]
    for origin, relative in resources:
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(origin, target)
    return [relative for _, relative in resources]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--model", type=Path, default=PROTOTYPE / "export/maglev_train_cargo.glb",
                        help="Optional shape-pass GLB for an intermediate inspection.")
    parser.add_argument("--zip", type=Path, help="Also package the clean Godot sources and assets.")
    args = parser.parse_args()
    resources = stage(args.destination, args.model)
    if args.zip:
        with zipfile.ZipFile(args.zip, "w", zipfile.ZIP_DEFLATED) as archive:
            for relative in resources:
                archive.write(args.destination / relative, relative)
    print(args.destination.resolve())


if __name__ == "__main__":
    main()
