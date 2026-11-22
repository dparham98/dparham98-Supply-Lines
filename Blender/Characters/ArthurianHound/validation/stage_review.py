"""Stage a portable Godot project from the working hound asset."""
import argparse
from pathlib import Path
from shutil import copy2
from zipfile import ZIP_DEFLATED, ZipFile

PACKAGE = Path(__file__).resolve().parents[1]

def stage(destination, archive=None):
    files = [(PACKAGE / "godot/project.godot.in", "project.godot"),
             (PACKAGE / "godot/README.md", "README.md")]
    for path in sorted((PACKAGE / "godot").iterdir()):
        if path.suffix in {".gd", ".tscn"}:
            files.append((path, "godot/" + path.name))
    files.extend([(PACKAGE / "export/arthurian_hound.glb", "export/arthurian_hound.glb"),
                  (PACKAGE / "validation/check_hound.gd", "validation/check_hound.gd")])
    for source, name in files:
        path = destination / name
        path.parent.mkdir(parents=True, exist_ok=True)
        copy2(source, path)
    if archive:
        archive.parent.mkdir(parents=True, exist_ok=True)
        with ZipFile(archive, "w", compression=ZIP_DEFLATED, compresslevel=6) as out:
            for _, name in files:
                out.write(destination / name, name)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--zip", type=Path)
    args = parser.parse_args()
    stage(args.destination, args.zip)
