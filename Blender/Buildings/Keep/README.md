# Arthurian Keep

The [editable Keep](Keep.blend) is the headquarters for the Knights settlement. Founding one costs 50 Wood and 50 Iron. The pointed oak portals carry the roof and the receiving canopy. Iron shoes take their weight at ground level, and iron plates protect the corners. The standing seams on the indigo roof lead up to the balloon dock. Banners and shield fields take the owner's team color.

The sally port faces Blender −Y and Godot +Z. It serves the Forester Maidens and Warhounds trained inside. The covered receiving bay faces −X. The four hinged clamps and status lights sit around the central mooring deck.

| Animation | Visible action |
| --- | --- |
| Idle | The Keep stands ready with the sally port closed. |
| Build | The construction site reveals the structure as work progresses. |
| Train | The gate lifts for the departing unit and closes behind it. |
| LaunchBalloon | The clamps release and reset around the clear rooftop dock. |
| Die | The structure collapses with a separate, synchronized Death effect. |

### Source and export

Run these commands from this folder with Blender 4.5. The first two rebuild the editable model. The third writes the game exports into the project's asset folders.

```text
blender -b --factory-startup --python-exit-code 1 -P build/build_keep.py
blender -b Keep.blend --python-exit-code 1 -P build/animate_keep.py
blender -b Keep.blend --python-exit-code 1 -P build/export_keep.py -- --to-assets
```

To check a fresh export, run the export command without `-- --to-assets` and then run `blender -b --factory-startup --python-exit-code 1 -P build/check_keep.py`. To render the studio view, run `blender -b Keep.blend -P build/render_keep.py`.

[Design reference](../../References/ArthurianCivilian/Keep_timber_and_iron_concept.png) · [Studio view](../../Previews/Keep/keep.png) · [Gameplay preview](../../Previews/Keep/keep_in_game.mp4)
