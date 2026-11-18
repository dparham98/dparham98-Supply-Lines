# Guideway renders

The eight views use the four gameplay track scenes at their authored wrapper scale. The red Streamliner follows the quarter curve, and the green Streamliner occupies a connected straight. The left turnout is set to the branch and the right turnout to the main line.

The yard uses the map's sky, sun and grass shader with the 72 m orthographic span, 50° pitch and 0° yaw of the starting gameplay camera. The close views use a matte floor and a fill light. The original and revised straight views share a camera and display the game's unpowered, powered and hostile status colors. The original mesh and scene are read from commit `0630a6129aa6968874552fbd914cafd40fe63ac0`.

From the repository root, run Python with Pillow installed and a Godot 4.7.2 executable. The script stages a temporary Godot project, imports its resources, captures eight frames and writes the four PNGs in `../preview/`. Pass `--raw DIRECTORY` to keep the individual captures.

```powershell
python Blender/Vehicles/Maglev/Guideway/review/render_review.py --godot C:/Dev/Tools/Godot_v4.7.2-stable_win64_console.exe
```
