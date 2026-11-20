# Ubermech

The Cyborg faction’s giant walker stands 5.16 m tall including its aerials. The shoulder cog, flanged field helmet, red optic, armored coat and mismatched forearms follow the [concept](source/concept.png). Shoulder, forearm and leg stripes take the owning side’s paint. The optic, reactor lights, emitter and six pod caps retain their red finish.

## In the game

Open Two Lakes to see the enemy Ubermech at its starting camp. The Tank Factory produces the playable unit through its existing Ubermech order. The [actor](../../../scenes/gameplay/ubermech.tscn) uses the saved [model scene](../../../scenes/models/ubermech_model.tscn). Movement drives the walk speed and the regular attack plays the emitter-arm action. The six-port pod is part of the model.

[Model in Two Lakes](preview/two_lakes.png) · [Movement reel](preview/ubermech_motion.mp4) · [Front](preview/ubermech.png) · [Back](preview/rear.png) · [Face](preview/portrait.png)

## Edit the model

Open [Ubermech.blend](source/Ubermech.blend) in Blender 4.5. The 650 editable parts are attached to the joints of **Ubermech Rig**. The original armor retains its editable chamfers and the three metal finishes are packed. Frame 0 is the neutral model pose. In the NLA Editor, solo **Rest**, **Walk** or **Shoot** to inspect a clip. The 36-frame walk cycle is authored at 30 fps and 3.10 m/s. The 18-frame firing clip moves the emitter, with the muzzle joint centered on its outer lens.

The [game GLB](../../../assets/models/units/ubermech.glb) combines the armor into one skinned mesh with 18 joints and 13 material surfaces. Its highest-detail mesh has 62,049 triangles. The Godot wrapper turns the glTF into the project’s −Z travel direction.

From the character folder, run these commands to publish saved Blender edits and regenerate the studio views.

```text
blender -b source/Ubermech.blend -P source/build.py -- --publish-open
blender -b --factory-startup -P source/studio.py -- --views ubermech portrait rear
```

To reconstruct the editable Blender file and game mesh from the modeling scripts, use `blender -b --factory-startup -P source/build.py`.

## Verify in Godot

The [runtime check](validation/check_ubermech.gd) loads Two Lakes, produces a unit through the factory, drives a terrain move, fires at a target and measures the rig, equipment paint and selection bounds. Run it from the Supply Lines checkout after Godot imports the GLB.

```text
godot --headless --path . --script Blender/Characters/Ubermech/validation/check_ubermech.gd
```

The [recorded measurements](validation/game_checks.json) include the game model’s SHA-256.
