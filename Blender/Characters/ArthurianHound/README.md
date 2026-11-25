# Arthurian hound

The Round Table's armored hound is sized alongside the Arthurian marines. Its dark coat, ivory helmet and saddle, blue armor, gold-edged heraldry and lit visor follow the supplied concept.

[Editable Blender model](source/Arthurian_Hound.blend) · [Godot model scene](../../../scenes/models/arthurian_hound_model.tscn) · [Game-ready GLB](export/arthurian_hound.glb) · [Full-body view](preview/hound.png) · [Head detail](preview/portrait.png) · [Rear view](preview/rear.png)

The [Godot review](validation/Arthurian_Hound_Review.zip) opens as a separate project. Drag to orbit, use the wheel to zoom, press 1 or 2 for the full model or head, and press Space to switch between the two animations. The [import report](validation/import_report.json) records the model's size, materials and rig checks. To regenerate the portable review, run `python Blender/Characters/ArthurianHound/validation/stage_review.py <output-folder> --zip Blender/Characters/ArthurianHound/validation/Arthurian_Hound_Review.zip`.

The hound stands about 1.28 m to the ear tips, with its origin at ground level. The [movement preview](preview/motion.mp4) shows the two looping clips. `Rest` lasts 2.67 seconds and brings the ears, head and tail to attention. `Run` is a 0.83-second diagonal trot authored in place for travel at 1.45 m/s. Both clips use the same 22-joint skeleton. The helmet stripe, shoulder and hip armor and breast tabard share the team paint. The ivory armor and metallic heraldry have fixed finishes.

Use the Godot model scene in a unit's Visuals slot. It provides the game's forward orientation and responds to the shared movement animator. The editable source keeps the fitted parts separate. Its export combines them into one skinned mesh.

From the project root, rebuild the Blender source and GLB with Blender 4.5, then render the previews.

```powershell
$blender = 'C:/Program Files/Blender Foundation/Blender 4.5/blender.exe'
& $blender -b --factory-startup --python-exit-code 1 -P Blender/Characters/ArthurianHound/source/build.py
& $blender -b --factory-startup --python-exit-code 1 -P Blender/Characters/ArthurianHound/source/studio.py
```
