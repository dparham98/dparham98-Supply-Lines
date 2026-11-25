"""Select the matching model and HUD portrait for the playable Grenadier."""
import argparse
from pathlib import Path
import os
import time
from tempfile import NamedTemporaryFile

def replace(path, data):
    with NamedTemporaryFile(dir=path.parent, suffix=".tmp", delete=False) as pending:
        temp = Path(pending.name)
        try:
            pending.write(data)
        except BaseException:
            pending.close()
            temp.unlink(missing_ok=True)
            raise
    try:
        os.replace(temp, path)
    finally:
        temp.unlink(missing_ok=True)

def select(look):
    art = Path(__file__).resolve().parent
    project = art.parents[2]
    if not (project/"project.godot").is_file():
        raise RuntimeError("Run the script from the Grenadier character folder inside Supply Lines.")
    sources = art / "looks" / look
    updated = [(project/"assets/models/units/grenadier.glb", (sources/"grenadier.glb").read_bytes()),
               (project/"assets/ui/portraits/grenadier.png", (sources/"grenadier.png").read_bytes())]
    originals = {path: path.read_bytes() if path.is_file() else None for path, _ in updated}
    # Godot can compare file modification times at whole-second resolution.
    # Two successive local selections must receive distinct timestamps.
    stamp = time.time()
    if any(originals[p] != data and p.exists() and int(p.stat().st_mtime) == int(stamp) for p,data in updated):
        time.sleep(int(stamp) + 1.01 - stamp)
    applied = []
    try:
        for path, data in updated:
            if data != originals[path]:
                replace(path, data)
                applied.append(path)
    except BaseException:
        for path in reversed(applied):
            if originals[path] is None:
                path.unlink(missing_ok=True)
            else:
                replace(path, originals[path])
        raise
    print("Selected the Grenadier model and HUD portrait:", look)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("look", choices=["Goggles","NoGoggles"])
    select(parser.parse_args().look)
