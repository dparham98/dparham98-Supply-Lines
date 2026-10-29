# Camera rig

Open scenes/camera/rts_camera.tscn and select CameraRig, the root node. All tuning controls are here. In the world scene, selecting the CameraRig instance lets you override settings for that map.

The hierarchy is CameraRig (ground focus) > YawPivot (rotation) > PitchPivot (tilt) > Camera (orthographic projection). Keep the rig parent untransformed. Change exported settings instead of manually moving its child camera.

| Control | Action |
| --- | --- |
| Arrow keys / screen edges | Pan relative to the camera |
| Shift | Faster pan |
| Middle mouse drag | Grab the ground |
| Mouse wheel | Smooth zoom toward cursor |
| Q / E | Rotate |
| F | Focus headquarters |
| Home | Frame selected player units |
| M | Fit whole map / return to previous view |

Starting View chooses HQ, authored ground position, or whole map. Default Zoom sets runtime scale; Editor Preview > Preview Zoom controls the saved/editor preview independently. Pitch and Yaw apply to both. Movement and Zoom And Orbit control speed, smoothing, zoom limits and optional edge pan. Actions can be remapped under Project Settings > Input Map (camera_*); A and right click retain unit commands.

Map Bounds is an X/Z rectangle. Constrain View To Map clamps the visible ground footprint, including rotation and aspect ratio. When the view is larger than the map, that axis centers. This also limits cursor anchoring near boundaries. Overview fits the whole map at any window aspect ratio and can exceed the ordinary manual zoom limit. Edge or keyboard navigation leaves overview and smoothly returns to the default navigation zoom so the map can move. O restores the view saved before entering it; navigating away from overview starts a new view.

UI blocks wheel/drag starts. Interactive UI blocks edge pan; the read-only terrain legend explicitly permits it. An owned drag releases even over UI, and losing window focus cancels it. Keyboard movement remains available while the pointer is over the legend.

Ground targeting assumes a flat Y=0 map. Elevated terrain, collision-aware camera movement and perspective projection are not supported. The rig is orthographic; see the official [Camera3D reference](https://docs.godotengine.org/en/4.3/classes/class_camera3d.html).

tests/camera_test.gd covers zoom anchoring and limits, rotated bounds, pan frame-rate consistency, rotation release, drag release/focus loss, aspect-ratio fitting, overview restoration, HQ and selection framing. Full map rendering and selection/navigation are checked by terrain_test.gd. These are automated checks, not a manual usability certification.

Edge panning uses a 64-pixel activation band. Entering a band acts like holding its arrow key, including identical speed, acceleration, stopping response, Shift boost and normalized diagonal movement. Both use Pan Speed and Pan Response; there are no separate edge speed or braking settings. Keyboard takes precedence over edges. tests/edge_pan_test.gd compares edge and arrow movement, including release and Shift at a rotated view.
