# Bastion in Godot

Extract `Bastion_Godot_Review.zip` into an empty folder outside Supply Lines. Import its `project.godot` into Godot 4.7.2 and press **F6** with `review.tscn` open, or **F5** from the project. The included tank wrappers, models, materials, lighting and scripts let this copy run independently.

| Control | Action |
| --- | --- |
| Left / Right or Space | Step through the six saved views |
| A / D | Orbit the current view |
| Mouse wheel | Zoom |
| C | Swap the two Bastions' paint |
| H | Toggle the legend |

The front, side, rear and team views use a matte floor and a studio fill alongside the map's sky and sun. The accepted tank uses the same front camera and light as the Bastion. The gameplay view places the accepted tank on the left, the red Bastion in the middle and the blue Bastion on the right. It uses the project's grass material, Two Lakes' sun and sky, and the opening camera at a 72 m orthographic span and 50° pitch.

The two Bastions use the same GLB. The review calls the game's `TeamPaint.apply()` using the normal red enemy paint and the blue player swatch from the approved infantry review. The playable project's player swatch is green. The stationary poses keep the turrets centred. The screenshot run also repaints the blue instance neutral and back, checks each team surface, and verifies that the neutral surfaces and the other instance retain their materials.

From the Supply Lines checkout, run the following with Python, Pillow and the pinned Godot executable to stage the dependencies, regenerate the ZIP, extract and import it in a scratch directory, and save the Godot captures beside the Blender source.

```powershell
python Blender/Vehicles/Tank/Astra_Bastion/validation/review/build_review.py --godot C:/Dev/Tools/Godot_v4.7.2-stable_win64_console.exe
```
