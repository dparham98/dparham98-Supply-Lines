"""Export edits from the open Bastion.blend with the accepted running-gear vertex order."""
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
sys.dont_write_bytecode = True
sys.path.insert(0,str(HERE))
from gear_export import export_tank

if __name__ == '__main__':
    destination = HERE.parent / 'export/Bastion.glb'
    destination.parent.mkdir(exist_ok=True)
    export_tank(destination)
