# Ubermech

The Cyborg faction’s giant walker stands 5.16 m tall including its aerials. The shoulder cog, flanged field helmet, red optic, armored coat and mismatched forearms follow the [concept](source/concept.png). Shoulder, forearm and leg stripes take the owning side’s paint. The optic, reactor lights, emitter and six pod caps retain their red finish.

## In the game

Open Two Lakes to see the enemy Ubermech at its starting camp. The Tank Factory produces it through the Ubermech order. The [actor](../../../scenes/gameplay/ubermech.tscn) uses the saved [model scene](../../../scenes/models/ubermech_model.tscn). Movement drives the walk speed. Each walker alternates a red laser pulse and a six-round pod volley on successive attacks. Each attack uses the existing 12-damage strike and five-second base cooldown.

[Both weapons in Two Lakes](preview/two_lakes.png) · [Combat and walking reel](preview/ubermech_motion.mp4) · [Front](preview/ubermech.png) · [Back](preview/rear.png) · [Face](preview/portrait.png)

## Edit the model

Open [Ubermech.blend](source/Ubermech.blend) in Blender 4.5. The 640 editable parts are attached to **Ubermech Rig**, including the folded collar, sliding emitter band and six pod caps. The armor retains its editable chamfers and the three metal finishes are packed. Frame 0 is the neutral pose. Solo a track in the NLA Editor to inspect its animation at 30 fps.

| Track | Action |
| --- | --- |
| Rest | A two-second idle loop |
| Walk | A 36-frame stride at 3.10 m/s |
| Shoot | The mech lifts and braces the emitter. The laser leaves the recessed lens on Blender frame 13, followed by recoil and recovery over a 1.2-second clip. |
| PodVolley | The mech raises the pod and releases ports 01, 04, 05, 02, 03 and 06 on Blender frames 13, 18, 23, 28, 33 and 38. The arm reacts to each release and the individual chambers reload before the two-second clip ends. |

The [game GLB](../../../assets/models/units/ubermech.glb) combines the armor into one skinned mesh with 31 joints and 13 material surfaces. Its highest-detail mesh has 62,512 triangles. The Godot wrapper turns the glTF into the project’s −Z travel direction.

From the character folder, run these commands to publish saved Blender edits and regenerate the studio views.

```text
blender -b source/Ubermech.blend -P source/build.py -- --publish-open
blender -b --factory-startup -P source/studio.py -- --views ubermech portrait rear
```

To reconstruct the editable Blender file and game mesh from the modeling scripts, use `blender -b --factory-startup -P source/build.py`.

## Verify in Godot

The [runtime check](validation/check_ubermech.gd) produces a walker at the Two Lakes factory and moves it across terrain. It checks the beam against the center of the lens, each pod round against its animated tube, and the damage and timing of consecutive attacks. It also interrupts each arm during windup and verifies the next attack still uses that arm. Run it from the Supply Lines checkout after Godot imports the GLB.

```text
godot --headless --path . --script Blender/Characters/Ubermech/validation/check_ubermech.gd
```

The [recorded measurements](validation/game_checks.json) include the game model’s SHA-256.
