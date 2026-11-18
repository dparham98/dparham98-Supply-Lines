"""Lay out the Godot framebuffer captures as review plates. Requires Pillow."""
import argparse
from pathlib import Path
import shutil

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
PAPER = (239, 239, 232)
INK = (29, 35, 35)
GREY = (70, 78, 77)
RED = (153, 48, 39)
RESAMPLE = Image.Resampling.LANCZOS


def font(size, heavier=False):
    for path in [
        "C:/Windows/Fonts/bahnschrift.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if heavier else
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    ]:
        if Path(path).is_file():
            face = ImageFont.truetype(path, size)
            if heavier and path.endswith("bahnschrift.ttf"):
                face.set_variation_by_name("Bold")
            return face
    return ImageFont.load_default(size=size)


def label(canvas, xy, text, size, color=INK, bold=False, anchor=None):
    ImageDraw.Draw(canvas).text(xy, text, font=font(size, bold), fill=color, anchor=anchor)


def header(canvas, title, detail):
    draw = ImageDraw.Draw(canvas)
    width = canvas.width
    draw.rectangle((0, 0, width, 110), fill=INK)
    label(canvas, (36, 15), "SUPPLY LINES  /  VEHICLE ART", 16, (191, 198, 187))
    label(canvas, (35, 39), title, 48, PAPER, True)
    label(canvas, (width - 36, 74), detail, 19, PAPER, anchor="rm")


def produce(raw, output):
    output.mkdir(parents=True, exist_ok=True)

    def shot(name):
        with Image.open(raw / (name + ".png")) as frame:
            if frame.size != (1280, 900):
                raise ValueError(f"{name} was rendered at {frame.size}, expected (1280, 900)")
            return frame.convert("RGB")

    def write(canvas, name):
        canvas.save(output / name, optimize=True)

    hero = Image.new("RGB", (1280, 890), PAPER)
    header(hero, "Industrial Streamliner", "MAGLEV  /  THREE-QUARTER VIEW")
    hero.paste(shot("hero").crop((0, 83, 1280, 808)), (0, 110))
    label(hero, (36, 850), "Self-powered cargo car", 22, INK, True)
    label(hero, (1244, 863), "Godot 4.7.2  /  Forward+", 18, GREY, anchor="rm")
    write(hero, "01_streamliner.png")

    views = Image.new("RGB", (1380, 872), PAPER)
    header(views, "Body and running gear", "SIDE  /  ELEVATED")
    for i, (name, title, box, subtitle) in enumerate([
        ("side", "Side elevation", (0, 96, 1280, 800), "Sled housings, coupler ends and nose profile"),
        ("elevated", "Elevated inspection", (0, 86, 1280, 790), "Shoulder paint, cargo cover and machinery spine"),
    ]):
        x = 28 + i * 676
        img = shot(name).crop(box).resize((648, 357), RESAMPLE)
        views.paste(img, (x, 143))
        label(views, (x, 526), title, 32, INK, True)
        label(views, (x, 576), subtitle, 21, GREY)
    ImageDraw.Draw(views).line((28, 631, 1352, 631), fill=(181, 186, 179))
    label(views, (28, 678), "Cargo indicator", 31, INK, True)
    label(views, (28, 731), "The amber bar rises 0.192 m in game", 21, GREY)
    label(views, (28, 765), "when the train carries cargo.", 21, GREY)
    for i, (name, caption) in enumerate([("elevated", "Empty"), ("loaded_indicator", "Loaded")]):
        x = 608 + 381 * i
        patch = shot(name).crop((779, 196, 1031, 340)).resize((294, 168), RESAMPLE)
        views.paste(patch, (x, 671))
        label(views, (x, 641), caption, 21, INK, True)
    write(views, "02_side_and_elevated.png")

    compare = Image.new("RGB", (1650, 680), PAPER)
    header(compare, "Vehicle comparison", "MATCHED SCALE  /  CAMERA  /  LIGHT")
    items = [("match_old", "Original train", "Accepted self-powered cargo car"),
             ("match_new", "Industrial Streamliner", "Redesign on the same running gear pivots"),
             ("match_truck", "Cargo truck", "Accepted six-wheel road vehicle")]
    for i, (name, title, subtitle) in enumerate(items):
        x = 28 + i * 542
        patch = shot(name).crop((200, 190, 1080, 750)).resize((510, 325), RESAMPLE)
        compare.paste(patch, (x, 145))
        label(compare, (x, 491), title, 31, INK, True)
        label(compare, (x, 545), subtitle, 20, GREY)
    label(compare, (28, 620), "All vehicles share the 0.6 gameplay scale and face the same direction. Truck and train use the same enemy paint.", 20, GREY)
    write(compare, "03_vehicle_comparison.png")

    teams = Image.new("RGB", (1280, 1060), PAPER)
    header(teams, "Team assignments", "TWO INSTANCES  /  ONE GLB")
    teams.paste(shot("teams").crop((0, 70, 1280, 845)), (0, 110))
    label(teams, (35, 922), "Gameplay distance", 30, INK, True)
    label(teams, (35, 969), "1:1 crop from the 1280 × 900 frame", 21, GREY)
    label(teams, (35, 1002), "72 m orthographic view  /  50° pitch", 21, GREY)
    teams.paste(shot("game").crop((370, 314, 920, 444)), (681, 906))
    write(teams, "04_team_colors.png")

    shutil.copyfile(raw / "game.png", output / "05_gameplay_distance.png")

    sheet = Image.new("RGB", (1320, 940), (246, 246, 244))
    header(sheet, "Silhouette study", "EQUAL SCALE  /  VEHICLE GEOMETRY")
    for row, (mode, title) in enumerate([("side", "Side elevation"), ("roof", "Gameplay angle")]):
        y = 171 + row * 389
        label(sheet, (29, y-31), title, 23, GREY)
        for col, variant in enumerate(["new", "truck"]):
            x = 29 + col * 647
            image = shot(f"mask_{variant}_{mode}").crop((210, 220, 1070, 670))
            image = image.resize((618, 324), RESAMPLE)
            sheet.paste(image, (x, y))
            label(sheet, (x+17, y+15), "Industrial Streamliner" if col == 0 else "Cargo truck", 23, INK, True)
    write(sheet, "06_silhouettes.png")


def shape_plate(raw, output):
    canvas = Image.new("RGB", (1160, 724), PAPER)
    header(canvas, "Shape pass", "GAMEPLAY CAMERA  /  MATCHED MODELS")
    for i, (name, text) in enumerate([("match_new", "Streamliner blockout"), ("match_truck", "Cargo truck")]):
        x = 18 + i * 570
        patch = Image.open(raw / (name + ".png")).crop((170, 145, 1110, 735))
        canvas.paste(patch.resize((550, 346), RESAMPLE), (x, 158))
        label(canvas, (x, 123), text, 23, INK, True)
    label(canvas, (21, 553), "Balanced Skirmish camera", 29, INK, True)
    label(canvas, (21, 602), "72 m orthographic  /  50° pitch", 22, GREY)
    label(canvas, (21, 640), "1:1 crop from the 1280 × 900 frame", 20, GREY)
    with Image.open(raw / "game.png") as frame:
        canvas.paste(frame.crop((375, 348, 925, 564)), (591, 506))
    canvas.save(output, optimize=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("frames", type=Path)
    parser.add_argument("--output", type=Path, default=HERE.parent.parent / "preview")
    parser.add_argument("--shape", type=Path, help="Write only the shape comparison to this PNG.")
    args = parser.parse_args()
    if args.shape:
        shape_plate(args.frames, args.shape)
    else:
        produce(args.frames, args.output)
