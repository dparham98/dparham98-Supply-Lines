"""Stage the opt-in Bastion variant alongside the accepted tank in a disposable Supply Lines project."""
import argparse
from pathlib import Path
import shutil


HERE = Path(__file__).resolve().parent
ROOT = next(path for path in HERE.parents if (path / "project.godot").is_file())
EXPORT = HERE.parent / "export/Bastion_AutoTurret.glb"
TANK_MODEL = "scenes/models/tank_model.tscn"
TANK_ACTOR = "scenes/gameplay/tank.tscn"


def substitute(scene, old, new):
    if scene.count(old) != 1:
        raise ValueError(f"Expected one reference to {old!r} in the accepted scene")
    return scene.replace(old, new, 1)


def stage_model(project: Path):
    """Stage the model, rig and controller. The model on its own is inert."""
    directory = Path(project) / "bastion"
    directory.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(EXPORT, directory / "variant.glb")
    for name in ("close_defense.gd", "aux_bullet.tscn", "aux_bullet.gd"):
        shutil.copyfile(HERE / name, directory / name)
    model = (ROOT / TANK_MODEL).read_text(encoding="utf-8")
    model = substitute(model, "res://assets/models/units/tank.glb", "res://bastion/variant.glb")
    (directory / "bastion_model.tscn").write_text(model, encoding="utf-8")


def stage(project: Path):
    """Keep the production actor, selection, stats and main cannon. Give this variant its own scene."""
    project = Path(project)
    stage_model(project)
    actor = (ROOT / TANK_ACTOR).read_text(encoding="utf-8")
    actor = substitute(actor, "res://" + TANK_MODEL, "res://bastion/bastion_model.tscn")
    first_resource = actor.index("[ext_resource")
    actor = (actor[:first_resource]
             + '[ext_resource type="Script" path="res://bastion/close_defense.gd" id="aux"]\n'
             + actor[first_resource:])
    actor += '\n[node name="CloseDefense" type="Node" parent="."]\nscript = ExtResource("aux")\n'
    (project / "bastion/bastion_tank.tscn").write_text(actor, encoding="utf-8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project", type=Path, help="Path to a disposable copy of the game")
    stage(parser.parse_args().project)
