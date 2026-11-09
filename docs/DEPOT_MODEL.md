# Depot model

The Depot uses the authored tarp warehouse with its tractor unit. The working file is `Blender/Buildings/Depot/Depot.blend`, and only its `depot_warehouse` collection is exported to `assets/models/buildings/depot.glb`. The model has no animations.

- `scenes/models/depot_model.tscn` places the model at world scale 0.6, the same as the vehicles. It turns the long axis east-west with the tractor facing east, and centres the model on the Depot.
- At that scale the model is about 16.3 m long, 9.3 m wide and 6.3 m tall, so the Depot footprint is now 17 by 10 tiles (`footprint` in `scripts/gameplay/depot.gd`). Depot Trucks need that much empty buildable land to deploy.
- `dropoff_range` is now 11.5 m. As before, it reaches every cell around the footprint, including the corners.
- Crates are set down from the footprint's short side outward, so they still land beside the long walls.
- Team colour on the tarp and tractor is left as authored; the Depot had no team colouring before this.
- The previous prototype stays at `scenes/models/depot_prototype.tscn` and is no longer used by the Depot.
- Check: `tests/depot_model_runtime_check.gd` (on the ground, inside the footprint, at scale, pickable).
