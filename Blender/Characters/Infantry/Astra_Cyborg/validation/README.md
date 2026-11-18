# Godot character review

Extract `Cyborg_Review.zip` outside the gameplay checkout. Import `project.godot` in Godot 4.7.2 and press **F5**. Both figures use the same animated infantry GLB.

| Control | Action |
| --- | --- |
| Left / Right | Play Rest, Run, Hack, Shoot or Die |
| A / D | Rotate both figures |
| R / B | Reassign the left or right figure independently |

The review uses the project’s infantry wrapper, character animator, tooth shader, muzzle light, death effect and team-paint script. Its red is the game’s enemy material. The player material is blue for this comparison. The gameplay player material is green. The wrapper assigns bright steel to the saw in Godot.

The [rear inspection frame](rear_inspection.png) shows the back yokes and nape guards at rest.

The following PowerShell reproduces the checks from the Supply Lines root. The review script uses Python 3 with Pillow to lay out its two rendered frames. The game test script uses the Python standard library.

```powershell
$validation = 'Blender/Characters/Infantry/Astra_Cyborg/validation'
$godot = 'C:/Dev/Tools/Godot_v4.7.2-stable_win64_console.exe'
python -B "$validation/verify_review.py" --godot $godot
python -B "$validation/verify_game.py" --godot $godot
```

[Godot review measurements](godot_checks.json) record bone count, clip length and looping, sampled joint motion, muzzle-light response and independent paint changes measured in rendered pixels. [Production checks](game_checks.json) record the unmodified model, death and skirmish rendering tests run with the exported GLB in a freshly imported disposable copy of the game.
