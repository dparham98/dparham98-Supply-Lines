"""Stage, pack and render the Bastion with the playable tank wrapper in a separate Godot project."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import zipfile

from PIL import Image, ImageDraw, ImageFont


HERE = Path(__file__).resolve().parent
PACKAGE = HERE.parents[1]
GAME = next(parent for parent in PACKAGE.parents if (parent / "project.godot").is_file())
MODEL = "assets/models/units/tank.glb"
WRAPPER = "scenes/models/tank_model.tscn"
REVIEW_GRASS = GAME / "Blender/Vehicles/Maglev/Astra_Streamliner/validation/review/grass_stage.tres"
REVIEW_BLUE = GAME / "Blender/Characters/Infantry/Astra_Cyborg/validation/review_player.tres"
ARCHIVE = PACKAGE / "validation/Bastion_Godot_Review.zip"
RES_PATH = re.compile(r'["\']res://([^"\']+\.(?:gd|gdshader|tres|tscn|png|glb))["\']')


def stage(destination, model):
    visited = set()

    def copy_resource(relative):
        if relative in visited:
            return
        visited.add(relative)
        source = GAME / relative
        if relative == "assets/materials/units/team_paint_player.tres":
            source = REVIEW_BLUE
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        import_settings = Path(str(source) + ".import")
        if import_settings.is_file():
            shutil.copyfile(import_settings, str(target) + ".import")
        if source.suffix in (".gd", ".tscn", ".tres", ".gdshader"):
            for dependency in RES_PATH.findall(source.read_text(encoding="utf-8")):
                copy_resource(dependency)

    for relative in [WRAPPER, "scenes/maps/lighting.tscn", "scripts/components/team_paint.gd"]:
        copy_resource(relative)
    shutil.copyfile(REVIEW_GRASS, destination / "grass_stage.tres")
    for dependency in RES_PATH.findall(REVIEW_GRASS.read_text(encoding="utf-8")):
        copy_resource(dependency)
    for name in ("review.tscn", "review.gd", "project.godot"):
        shutil.copyfile(HERE / name, destination / name)
    (destination / "bastion").mkdir()
    shutil.copyfile(model, destination / "bastion/tank.glb")
    wrapper = (GAME / WRAPPER).read_text(encoding="utf-8")
    (destination / "bastion/tank_model.tscn").write_text(
        wrapper.replace("res://" + MODEL, "res://bastion/tank.glb"), encoding="utf-8")
    if (HERE / "README.md").is_file():
        shutil.copyfile(HERE / "README.md", destination / "README.md")


def run(engine, project, *args):
    profile = project.parent / "user_data"
    profile.mkdir(exist_ok=True)
    env = dict(os.environ, APPDATA=str(profile), LOCALAPPDATA=str(profile))
    command = [str(engine), "--path", str(project), "--log-file", str(profile / "review.log"), *args]
    result = subprocess.run(command, capture_output=True, timeout=360, env=env,
                            creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
    output = (result.stdout + result.stderr).decode("utf-8", errors="replace")
    if result.returncode or re.search(r"(?:SCRIPT )?ERROR:", output):
        raise RuntimeError(output[-12000:].encode("ascii","replace").decode())
    return output


def typeface(size):
    for filename in ("C:/Windows/Fonts/bahnschrift.ttf", "DejaVuSans.ttf"):
        try:
            return ImageFont.truetype(filename, size)
        except OSError:
            pass
    return ImageFont.load_default(size=size)


def plates(frames, previews):
    previews.mkdir(parents=True, exist_ok=True)
    for shot in ("front", "side", "rear", "teams", "gameplay"):
        shutil.copyfile(frames / (shot + ".png"), previews / (shot + ".png"))

    paper, ink = (238, 234, 224), (38, 40, 37)
    sheet = Image.new("RGB", (1540, 686), paper)
    draw = ImageDraw.Draw(sheet)
    draw.text((36,19), "Tank comparison", fill=ink, font=typeface(37))
    for column, (shot, label) in enumerate([("original","Accepted tank"),("front","Bastion")]):
        x = 36 + 740 * column
        with Image.open(frames / (shot + ".png")) as original:
            frame = original.convert("RGB").resize((730,513), Image.Resampling.LANCZOS)
        sheet.paste(frame,(x,85))
        draw.text((x,611),label,fill=ink,font=typeface(25))
    sheet.save(previews / "comparison.png")

    # Keep the full gameplay frame at its native 1280 × 900 resolution. The lower
    # strip magnifies the same pixels so panel visibility at play zoom is inspectable.
    with Image.open(frames / "gameplay.png") as image:
        game = image.convert("RGB")
    overview = Image.new("RGB", (1280, 1126), paper)
    overview.paste(game,(0,0))
    draw = ImageDraw.Draw(overview)
    draw.text((29,915),"Two Lakes",font=typeface(28),fill=ink)
    draw.text((30,956),"Starting gameplay camera",font=typeface(20),fill=ink)
    draw.text((30,989),"72 m span   /   50° pitch",font=typeface(17),fill=ink)
    draw.text((30,1035),"Full frame above at native scale.",font=typeface(16),fill=ink)
    draw.text((30,1061),"Detail crops shown at 2×.",font=typeface(16),fill=ink)
    for i, (cx,label) in enumerate(((490,"Accepted tank"),(640,"Bastion · red"),(790,"Bastion · blue"))):
        detail = game.crop((cx-59,405,cx+59,486)).resize((236,162), Image.Resampling.NEAREST)
        x = 410 + i * 278
        overview.paste(detail,(x,919))
        draw.text((x,1088),label,font=typeface(20),fill=ink)
    overview.save(previews / "gameplay_comparison.png")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--calibrate", action="store_true", help="Frame the accepted tank before the new GLB is ready.")
    mode.add_argument("--study", type=Path, help="Inspect an intermediate GLB in a disposable review.")
    parser.add_argument("--frames", type=Path, help="Keep uncropped camera images and the Godot check log.")
    args = parser.parse_args()
    model = args.study or (GAME / MODEL if args.calibrate else PACKAGE / "export/Bastion.glb")
    with tempfile.TemporaryDirectory(prefix="SupplyLines_Bastion_") as name:
        root = Path(name)
        source, project, frames = (root / n for n in ("staged", "verified", "frames"))
        for path in (source, project, frames):
            path.mkdir()
        stage(source,model)
        archive = root / ARCHIVE.name
        with zipfile.ZipFile(archive,"w",zipfile.ZIP_DEFLATED) as bundle:
            for path in sorted(source.rglob("*")):
                if path.is_file():
                    bundle.write(path,path.relative_to(source))
        with zipfile.ZipFile(archive) as bundle:
            bundle.extractall(project)
        run(args.godot,project,"--headless","--import")
        flags = ["--position","-4500,-4500","--resolution","1280x900","--audio-driver","Dummy",
                 "--","--capture",str(frames)]
        if args.calibrate:
            flags.append("--calibrate")
        print(run(args.godot,project,*flags)[-1800:].encode("ascii","replace").decode())
        if args.frames:
            shutil.copytree(frames, args.frames, dirs_exist_ok=True)
        if not (args.calibrate or args.study):
            reviewed_hash = hashlib.sha256((source / "bastion/tank.glb").read_bytes()).hexdigest()
            if hashlib.sha256(model.read_bytes()).hexdigest() != reviewed_hash:
                raise RuntimeError("The prototype changed during rendering. Repeat on the finished export.")
            plates(frames,PACKAGE / "preview")
            shutil.copyfile(archive,ARCHIVE)
            checks = json.loads((frames / "review_checks.json").read_text())
            checks["project_zip_sha256"] = hashlib.sha256(archive.read_bytes()).hexdigest()
            checks["prototype_glb_sha256"] = reviewed_hash
            (HERE / "verified.json").write_text(json.dumps(checks,indent=2)+"\n",encoding="utf-8")


if __name__ == "__main__":
    main()
