"""Stage a portable live range, render it in Godot, and package the checked project."""
import argparse
import hashlib
from pathlib import Path
import re
import runpy
import shutil
import sys
import tempfile
import zipfile

from PIL import Image

HERE = Path(__file__).resolve().parent
PACKAGE = HERE.parent
GAME = next(p for p in PACKAGE.parents if (p / 'project.godot').is_file())
sys.dont_write_bytecode = True
shared = runpy.run_path(str(PACKAGE.parent/'validation/review/build_review.py'))
run_godot = shared['run']
resource_paths = shared['RES_PATH']


def stage_range(project):
    stage_model = runpy.run_path(str(PACKAGE/'gameplay/stage_actor.py'))['stage_model']
    stage_model(project)
    for name in ('project.godot', 'range.tscn', 'range.gd', 'range_unit.gd'):
        shutil.copyfile(HERE/name, project/name)

    visited = set()
    def include(relative):
        if relative in visited:
            return
        visited.add(relative)
        dest = project/relative
        if not dest.is_file():
            source = GAME/relative
            if relative == 'assets/materials/units/team_paint_player.tres':
                source = shared['REVIEW_BLUE']
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source,dest)
            settings = Path(str(source)+'.import')
            if settings.is_file():
                shutil.copyfile(settings,str(dest)+'.import')
        if dest.suffix in ('.gd','.gdshader','.tscn','.tres'):
            for ref in resource_paths.findall(dest.read_text(encoding='utf-8')):
                include(ref)

    # Named classes referenced by type in CombatResolver are registered on import.
    for resource in ('range.tscn', 'scripts/units/unit_stats.gd', 'scripts/units/mobility_rules.gd'):
        include(resource)
    shutil.copyfile(HERE/'README.md',project/'README.md')


def save_motion(source, pattern, destination, count, size, duration):
    frames = []
    for path in sorted(source.glob(pattern)):
        with Image.open(path) as picture:
            frames.append(picture.convert('RGB').resize(size,Image.Resampling.LANCZOS))
    if len(frames) != count:
        raise RuntimeError('Incomplete motion capture for '+destination.name)
    frames[0].save(destination,save_all=True,append_images=frames[1:],
                   duration=duration,loop=0,quality=90,method=4)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', type=Path, required=True)
    args = parser.parse_args()
    preview = PACKAGE/'preview'
    preview.mkdir(exist_ok=True)
    (PACKAGE/'validation').mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='Bastion_range_') as temp:
        tmp = Path(temp)
        source = tmp/'source'
        source.mkdir()
        stage_range(source)
        archive = tmp/'Bastion_AutoTurret_Review.zip'
        with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as bundle:
            for path in sorted(source.rglob('*')):
                if path.is_file():
                    bundle.write(path,path.relative_to(source))
        verified = tmp/'verified'
        with zipfile.ZipFile(archive) as bundle:
            bundle.extractall(verified)
        run_godot(args.godot,verified,'--headless','--import')
        output = run_godot(args.godot,verified,'--position','-4500,-4500','--resolution','1280x820',
                           '--audio-driver','Dummy','--fixed-fps','60','--','--capture',str(tmp))
        if 'LIVE_RANGE main=' not in output:
            raise RuntimeError(output[-1200:])
        for name in ('turret.png','range.png'):
            shutil.copyfile(tmp/name,preview/name)
        save_motion(tmp,'yaw_*.png',preview/'traverse.webp',42,(720,461),83)
        save_motion(tmp,'bullet_*.png',preview/'bullets.webp',37,(920,589),67)
        shutil.copyfile(archive,PACKAGE/'validation'/archive.name)
        print(re.search(r'LIVE_RANGE .+',output).group())
        print('Range ZIP SHA256',hashlib.sha256(archive.read_bytes()).hexdigest())


if __name__=='__main__':
    main()
