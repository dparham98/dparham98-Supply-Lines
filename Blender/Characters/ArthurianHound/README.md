# Arthurian hound

The Round Table's armored hound is sized alongside the Arthurian marines. Its dark coat, ivory helmet and saddle, blue armor, gold-edged heraldry and lit visor follow the supplied concept.

[Editable Blender model](source/Arthurian_Hound.blend) · [Game-ready GLB](export/arthurian_hound.glb) · [Full-body view](preview/hound.png) · [Head detail](preview/portrait.png) · [Rear view](preview/rear.png)

The [Godot review](validation/Arthurian_Hound_Review.zip) opens as a separate project. Drag to orbit, use the wheel to zoom, and press 1 or 2 for the full model or head. The [import report](validation/import_report.json) records the model's size, materials and rig checks. To regenerate the portable review, run `python Blender/Characters/ArthurianHound/validation/stage_review.py <output-folder> --zip Blender/Characters/ArthurianHound/validation/Arthurian_Hound_Review.zip`.

The model has a ground-level origin and stands about 1.30 m tall to the ear tips. It contains an articulated skeleton and a neutral Rest clip. The head, forelegs, hind legs and tail have separate joints. The helmet stripe, shoulder shields, hip plates and chest tabard use the `team_color` material.

From the project root, rebuild the Blender source and GLB with Blender 4.5, then render the previews.

```powershell
$blender = 'C:/Program Files/Blender Foundation/Blender 4.5/blender.exe'
& $blender -b --factory-startup --python-exit-code 1 -P Blender/Characters/ArthurianHound/source/build.py
& $blender -b --factory-startup --python-exit-code 1 -P Blender/Characters/ArthurianHound/source/studio.py
```
