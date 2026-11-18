# Cyborg infantry

An editable interpretation of the supplied character sheet, built on Supply Lines' existing 22-bone infantry rig. The helmet stripe, epaulettes and back yoke share one team paint. The eye implant stays red for both teams.

| Open | File |
| --- | --- |
| Editable Blender character | [source/Cyborg_Infantry.blend](source/Cyborg_Infantry.blend) |
| Rigged game asset | [export/infantry.glb](export/infantry.glb) |
| Front, back and blue team views | [Character sheet](preview/character_sheet.png) |
| Head detail | [Studio portrait](preview/portrait.png) |
| Godot poses and color assignments | [In-engine preview](preview/godot_teams.png) |
| Interactive Godot project | [Cyborg_Review.zip](validation/Cyborg_Review.zip) |

Extract the ZIP outside the playable checkout, open its `project.godot` in Godot 4.7.2 and press **F5**. Left and Right cycle the animations. A and D turn the figures. R and B change their teams independently. The review uses a blue player material. The playable project's player material is green. Its infantry scene also assigns bright steel to the saw. [Godot review and test instructions](validation/README.md)

## Edit and export

The Blender source opens in Rest. Meshes for the face, optic, helmet, sleeves, mechanical arm, double-breasted coat, skirt halves and boots can be edited separately. The exporter combines the garment and facial meshes into one skinned body while keeping the named props, teeth, light and flash accessible to Godot. The supplied [concept sheet](source/concept.png) is the visual reference.

The GLB contains 7,564 triangles, six meshes, 25 PBR materials and zero textures. The accepted infantry contains 9,336 triangles, six meshes and eight materials. Re-exporting the saved prototype in Blender 4.5.3 reproduced the delivered GLB byte for byte.

Run these commands from the Supply Lines checkout in PowerShell. **Export hand edits** operates on the saved prototype. **Regenerate** rebuilds that prototype from the modeling scripts and the authoritative `Blender/Characters/Infantry/Infantry.blend` rig.

```powershell
$asset = 'Blender/Characters/Infantry/Astra_Cyborg'
$blender = 'C:/Program Files/Blender Foundation/Blender 4.5/blender.exe'

# Export hand edits
& $blender -b --factory-startup "$asset/source/Cyborg_Infantry.blend" --python-exit-code 1 -P "$asset/source/export_character.py"

# Regenerate the prototype and its GLB
& $blender -b --factory-startup --python-exit-code 1 -P "$asset/source/build.py"

# Render the Blender views and assemble the sheet (Python with Pillow)
& $blender -b --factory-startup "$asset/source/Cyborg_Infantry.blend" --python-exit-code 1 -P "$asset/source/render_studio.py"
python -B "$asset/source/make_sheet.py"
```

The source studio views use a relaxed wrist and a slight head turn for the portrait. The Godot review shows the exported Rest, Run, Hack, Shoot and Die clips. The stock model, death and rendered skirmish checks run against the export in a disposable game copy. [Animation and paint measurements](validation/godot_checks.json) · [Production checks](validation/game_checks.json)
