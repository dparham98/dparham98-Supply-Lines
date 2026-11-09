# Depot model

The Depot uses the authored tarp warehouse with its tractor unit. The working file is `Blender/Buildings/Depot/Depot.blend`, and only its `depot_warehouse` collection is exported to `assets/models/buildings/depot.glb`. The model has no animations.

- `scenes/models/depot_model.tscn` places the model at world scale 0.6, the same as the vehicles. It turns the model with the tractor facing east, and centres the tent on the Depot.
- At that scale the tent is about 10 m by 9.3 m and 6.3 m tall, so the Depot footprint is 10 by 10 tiles (`footprint` in `scripts/gameplay/depot.gd`). Depot Trucks need that much empty buildable land to deploy. The tractor and ramp stand outside the footprint, so units can cross them and they do not block building.
- The tractor and ramp carry the `not_selectable` metadata, so selection outlines and clicks use the tent only.
- `dropoff_range` is now 8.5 m. As before, it reaches every cell around the footprint, including the corners.
- Crates are set down from the footprint's shorter side outward.
- Team colour on the tarp and tractor is left as authored; the Depot had no team colouring before this.
- The previous prototype stays at `scenes/models/depot_prototype.tscn` and is no longer used by the Depot.
- Check: `tests/depot_model_runtime_check.gd` (the tent is on the ground, inside the footprint and pickable; the tractor is not pickable).
