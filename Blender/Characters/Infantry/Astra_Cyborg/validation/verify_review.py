"""Build a portable character review, freshly import it, exercise the animator and render it."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import zipfile

HERE = Path(__file__).resolve().parent
PACKAGE = HERE.parent
GAME = next(p for p in PACKAGE.parents if (p / "project.godot").is_file())
ASSET = Path("assets/models/units/infantry.glb")
DEPS = [
    "scenes/models/infantry_model.tscn", "scenes/models/infantry_death_fx.tscn",
    "scripts/components/character_animator.gd", "scripts/components/burst_effect.gd",
    "scripts/components/team_paint.gd", "assets/shaders/chainsaw_teeth.gdshader",
    "assets/materials/units/team_paint_enemy.tres", "assets/materials/units/team_paint_neutral.tres",
    str(ASSET) + ".import", "assets/models/effects/infantry_death_oil.glb",
    "assets/models/effects/infantry_death_oil.glb.import",
]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(engine, directory, *arguments):
    captures = directory.parent / "captures"
    captures.mkdir(exist_ok=True)
    env = dict(os.environ, APPDATA=str(directory.parent / "profile"),
               LOCALAPPDATA=str(directory.parent / "profile"),SUPPLY_LINES_TEST_OUTPUT=str(captures))
    cmd = [str(engine), "--path", str(directory), "--log-file", str(directory.parent / "engine.log"), *arguments]
    result = subprocess.run(cmd, capture_output=True, timeout=480, env=env,
                            creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
    output = (result.stdout + result.stderr).decode("utf-8", errors="replace")
    if result.returncode or "SCRIPT ERROR:" in output or "ERROR:" in output:
        raise RuntimeError(output[-16000:].encode("ascii","replace").decode())
    return output


def write_zip(archive, model):
    with zipfile.ZipFile(archive,"w",zipfile.ZIP_DEFLATED) as z:
        for name in ["project.godot","review.tscn","review.gd"]:
            z.write(HERE/name,name)
        for name in DEPS:
            z.write(GAME/name,name)
        z.write(HERE/"review_player.tres","assets/materials/units/team_paint_player.tres")
        z.write(model,ASSET)


def make_plate(frames, output):
    from PIL import Image, ImageDraw, ImageFont
    font_file = Path("C:/Windows/Fonts/bahnschrift.ttf")
    if not font_file.is_file():
        font_file = Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf")
    def font(size):
        return ImageFont.truetype(str(font_file),size) if font_file.exists() else ImageFont.load_default(size=size)
    bg = (236,234,226)
    ink = (40,43,41)
    image = Image.new("RGB",(1500,744),bg)
    d = ImageDraw.Draw(image)
    d.text((28,19),"Cyborg infantry",font=font(35),fill=ink)
    d.text((1474,35),"GODOT  /  CHARACTER REVIEW",font=font(16),fill=ink,anchor="rm")
    for i,(name,title,description) in enumerate([
        ("teams.png","Ownership","Red and blue instances at rest"),
        ("poses.png","Motion","Hack and Run sampled on the game skeleton")]):
        with Image.open(frames/name) as frame:
            frame = frame.convert("RGB").resize((718,513),Image.Resampling.LANCZOS)
        x = 28+i*724
        image.paste(frame,(x,83))
        d.text((x,617),title,font=font(26),fill=ink)
        d.text((x,655),description,font=font(19),fill=(69,73,70))
    d.text((28,718),"Supply Lines",font=font(14),fill=(83,86,81),anchor="ls")
    d.text((1473,718),"Godot 4.7.2   /   Forward+",font=font(14),fill=(83,86,81),anchor="rs")
    image.save(output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot",type=Path,required=True)
    parser.add_argument("--baseline",action="store_true",help="Calibrate using the accepted model.")
    parser.add_argument("--frames",type=Path,help="Optional destination for the captured native images.")
    args = parser.parse_args()
    model = GAME/ASSET if args.baseline else PACKAGE/"export/infantry.glb"
    with tempfile.TemporaryDirectory(prefix="SupplyLines_Cyborg_") as tmp:
        temp = Path(tmp)
        proj = temp/"project"
        frames = temp/"frames"
        frames.mkdir()
        archive = temp/"Cyborg_Review.zip"
        write_zip(archive,model)
        with zipfile.ZipFile(archive) as z:
            z.extractall(proj)
        run(args.godot,proj,"--headless","--import")
        arguments = ["--position","-4000,-4000","--resolution","1260x900",
                     "--audio-driver","Dummy","--","--capture",str(frames)]
        if args.baseline: arguments.append("--baseline")
        log = run(args.godot,proj,*arguments)
        print(log[-1900:].encode("ascii","replace").decode())
        data = json.loads((frames/"checks.json").read_text())
        data["renderer"] = next((line for line in log.splitlines() if "Forward+" in line),"")
        data["godot"] = subprocess.check_output([str(args.godot),"--version"],text=True).strip()
        data["glb_sha256"] = sha(model)
        data["project_zip_sha256"] = sha(archive)
        data["staged_game_files"] = DEPS
        if args.frames:
            args.frames.mkdir(exist_ok=True,parents=True)
            for name in ["teams.png","poses.png","rear.png"]:
                shutil.copy2(frames/name,args.frames/name)
        if not args.baseline:
            (PACKAGE/"preview").mkdir(exist_ok=True)
            make_plate(frames,PACKAGE/"preview/godot_teams.png")
            shutil.copy2(frames/"rear.png",HERE/"rear_inspection.png")
            shutil.copy2(archive,HERE/"Cyborg_Review.zip")
            (HERE/"godot_checks.json").write_text(json.dumps(data,indent=2)+"\n",encoding="utf-8")


if __name__ == "__main__":
    main()
