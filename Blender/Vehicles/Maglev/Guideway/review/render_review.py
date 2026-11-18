"""Render the game's four maglev track scenes in Godot and assemble their art plates."""

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from PIL import Image, ImageDraw, ImageFont, ImageOps


HERE = Path(__file__).resolve().parent
PACKAGE = HERE.parent
GAME = next(p for p in PACKAGE.parents if (p / "project.godot").is_file())
BASELINE = "0630a6129aa6968874552fbd914cafd40fe63ac0"
KINDS = ("straight", "curve", "fork_left", "fork_right")
INK = (32, 37, 36)
PAPER = (239, 239, 232)


def copy_resource(project, relative):
    destination = project / relative
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(GAME / relative, destination)


def stage(project):
    for resource in (
        "scripts/rails/track_piece.gd",
        "scripts/rails/rail_line.gd",
        "scripts/rails/train_consist.gd",
        "scripts/components/team_paint.gd",
        "scenes/models/train_model.tscn",
        "assets/models/units/maglev_train_cargo.glb",
        "assets/models/units/maglev_train_cargo.glb.import",
        "scenes/maps/lighting.tscn",
        "assets/shaders/terrain_surface.gdshader",
    ):
        copy_resource(project, resource)
    train_review = GAME / "Blender/Vehicles/Maglev/Astra_Streamliner/validation/review"
    shutil.copyfile(train_review / "grass_stage.tres", project / "grass_stage.tres")
    for channel in ("albedo", "normal"):
        for extension in (".png", ".png.import"):
            copy_resource(project, f"assets/textures/terrain/ground_tiles_{channel}{extension}")
    for team in ("player", "enemy", "neutral"):
        copy_resource(project, f"assets/materials/units/team_paint_{team}.tres")
    for kind in KINDS:
        copy_resource(project, f"scenes/gameplay/track_{kind}.tscn")
        copy_resource(project, f"assets/models/rails/maglev_track_{kind}.glb")
        copy_resource(project, f"assets/models/rails/maglev_track_{kind}.glb.import")

    original_mesh = "assets/models/rails/maglev_track_straight.glb"
    original_wrapper = "scenes/gameplay/track_straight.tscn"
    for resource, destination in ((original_mesh, "original.glb"), (original_wrapper, "original.tscn")):
        content = subprocess.check_output(["git", "show", f"{BASELINE}:{resource}"], cwd=GAME)
        if resource == original_wrapper:
            content = content.replace(original_mesh.encode(), b"original.glb")
        (project / destination).write_bytes(content)
    for name in ("review.tscn", "review.gd", "project.godot"):
        shutil.copyfile(HERE / name, project / name)


def run(engine, project, *args):
    profile = str(project.parent / "profile")
    environment = dict(os.environ, APPDATA=profile, LOCALAPPDATA=profile)
    command = [str(engine), "--path", str(project), "--log-file", str(project.parent / "engine.log"), *args]
    result = subprocess.run(
        command,
        env=environment,
        capture_output=True,
        timeout=160,
        creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0,
    )
    log = (result.stdout + result.stderr).decode("utf-8", errors="replace")
    if result.returncode or "ERROR:" in log:
        raise RuntimeError(log[-14000:].encode("ascii", "replace").decode())
    print(log[-600:].encode("ascii", "replace").decode())


def typography(size):
    for name in ("C:/Windows/Fonts/bahnschrift.ttf", "DejaVuSans.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default(size=size)


def panel(sheet, raw, shot, x, y, width, height):
    with Image.open(raw / f"{shot}.png") as frame:
        fitted = ImageOps.fit(frame.convert("RGB"), (width, height), method=Image.Resampling.LANCZOS)
        sheet.paste(fitted, (x, y))


def export_plates(raw, destination):
    destination.mkdir(parents=True, exist_ok=True)
    for shot, filename in (("hero", "streamliner_guideway"), ("yard", "yard")):
        with Image.open(raw / f"{shot}.png") as frame:
            frame.save(destination / f"{filename}.png", optimize=True)

    sheet = Image.new("RGB", (1480, 1070), PAPER)
    draw = ImageDraw.Draw(sheet)
    draw.text((34, 19), "SUPPLY LINES", font=typography(17), fill=INK)
    draw.text((32, 39), "Maglev guideway", font=typography(42), fill=INK)
    modules = (("straight", "Straight"), ("curve", "Quarter curve"),
               ("left", "Left turnout · branch selected"), ("right", "Right turnout · main selected"))
    for i, (shot, title) in enumerate(modules):
        x = 32 + (i % 2) * 716
        y = 111 + (i // 2) * 465
        panel(sheet, raw, shot, x, y, 699, 397)
        draw.text((x, y + 405), title, font=typography(26), fill=INK)
    sheet.save(destination / "guideway_kit.png", optimize=True)

    sheet = Image.new("RGB", (1480, 618), PAPER)
    draw = ImageDraw.Draw(sheet)
    draw.text((32, 23), "Straight guideway", font=typography(40), fill=INK)
    for i, (shot, title) in enumerate((("old", "Original"), ("new", "Revised"))):
        x = 32 + i * 716
        panel(sheet, raw, shot, x, 91, 699, 433)
        draw.text((x, 535), title, font=typography(26), fill=INK)
    sheet.save(destination / "straight_comparison.png", optimize=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=PACKAGE / "preview")
    parser.add_argument("--raw", type=Path, help="Keep the eight full-size camera captures")
    options = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="guideway_review_") as name:
        root = Path(name)
        project = root / "project"
        project.mkdir()
        raw = options.raw.resolve() if options.raw else root / "raw"
        raw.mkdir(parents=True, exist_ok=True)
        stage(project)
        run(options.godot, project, "--headless", "--import")
        run(
            options.godot, project, "--position", "-4800,-4800", "--resolution", "1600x1000",
            "--audio-driver", "Dummy", "--", "--capture", str(raw),
        )
        export_plates(raw, options.output)


if __name__ == "__main__":
    main()
