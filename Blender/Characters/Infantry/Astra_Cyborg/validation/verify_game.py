"""Run the accepted infantry checks with the new GLB in a disposable game copy."""
import argparse
import json
from pathlib import Path
import shutil
import tempfile

from verify_review import ASSET, GAME, HERE, PACKAGE, run, sha


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot",type=Path,required=True)
    args = parser.parse_args()
    model = PACKAGE/"export/infantry.glb"
    with tempfile.TemporaryDirectory(prefix="SupplyLines_Cyborg_Game_") as tmp:
        stage = Path(tmp)/"project"
        stage.mkdir()
        for name in ["assets","scripts","scenes","tests"]:
            shutil.copytree(GAME/name,stage/name)
        for name in ["project.godot","icon.svg","icon.svg.import","Camera.tscn"]:
            shutil.copy2(GAME/name,stage/name)
        shutil.copy2(model,stage/ASSET)
        run(args.godot,stage,"--headless","--import")
        passed = []
        for name,marker,display in [
                ("infantry_model_test","INFANTRY_MODEL_TEST_PASSED",["--headless"]),
                ("cyborg_death_test","CYBORG_DEATH_TEST_PASSED",["--headless"]),
                ("infantry_model_runtime_check","INFANTRY_MODEL_RUNTIME_CHECK_PASSED",
                 ["--position","-4000,-4000","--audio-driver","Dummy"])]:
            log = run(args.godot,stage,*display,"--script","res://tests/"+name+".gd")
            if marker not in log:
                raise RuntimeError(log[-5000:])
            print(marker)
            passed.append(marker)
        frames = sorted(p.name for p in (stage.parent/"captures").glob("infantry_*.png"))
        if len(frames) != 4:
            raise RuntimeError("Expected four skirmish screenshots, got "+str(frames))
        (HERE/"game_checks.json").write_text(json.dumps({
            "glb_sha256":sha(stage/ASSET),"stock_checks_passed":passed,"rendered_skirmish_frames":frames,
            "palette":"Original gameplay palette","infantry_model_wrapper_sha256":sha(stage/"scenes/models/infantry_model.tscn")
        },indent=2)+"\n",encoding="utf-8")


if __name__ == "__main__":
    main()
