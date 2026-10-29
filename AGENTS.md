# Supply Lines local working project

GitHub repository dparham98/dparham98-Supply-Lines is the authoritative source of version-controlled project files. C:\Dev\Supply-Lines is the primary Windows gameplay and art-testing checkout; cloud agents should use fresh repository clones and feature branches.
The old C:\Users\video\OneDrive\Documents\supply-lines-full copy is a preserved archive; do not update it or run it as the main project.
Use GitHub for collaboration through feature branches and pull requests. Preserve main as the accepted playable baseline; do not force-push or merge unverified work. Run cloud headless checks and obtain independent review plus human gameplay acceptance before merging gameplay changes.
Preserve assets/maps/source_map.png (the original Mini Map.png pixels). Terrain data is separate from the visual image; keep assets/maps/terrain_data.png lossless and read CPU categories from assets/maps/terrain_cells.bin.
The playable main scene is scenes/maps/resource_skirmish.tscn; scenes/maps/supply_lines_world.tscn is the preserved terrain/legacy review world. See docs/FIRST_CONTACT.md and RECOVERED_DESIGN.md for confirmed history and provisional mechanics. Keep rendering visible in saved editor scenes; gameplay scripts must not recreate terrain, lighting, UI or actor visuals at runtime. Use reusable actor scenes and their Visuals model slots. Terrain static props are assigned on terrain.tscn and regenerated using its Inspector button. Follow README.md and docs/ARCHITECTURE.md.
The Blender infantry working file is separate; do not create numbered .blend files for amendments.

Supply Lines Blender working files now live under C:\Dev\Supply-Lines\Blender. Use Characters\Scout\Scout.blend and Characters\Infantry\Infantry.blend for amendments; preserved Codex/OneDrive copies are historical. See Blender\README.md. Keep .gdignore to prevent Godot importing work-in-progress art.
