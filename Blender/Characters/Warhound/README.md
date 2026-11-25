# Supply Lines Warhound · revised run

[Watch the gallop](previews/Warhound-run.mp4) at real speed, then half speed. The [side-by-side comparison](previews/Warhound-run-comparison.mp4) shows the pilot trot at its authored 2 m/s on the left and the new gallop at 4 m/s on the right. Both views use the same camera and show the ground moving at the matching speed. The [fixed-camera pass](previews/Warhound-travel.mp4) shows the dog covering 7.5 m.

## Motion

The rear paws land in succession and drive the body forward. The forelegs reach for the ground, catch the weight, and fold under the chest as the hind legs swing through. The back changes shape and the tail follows the stride. The extended and gathered airborne poses are visible in the [pose sheet](previews/Warhound-run-poses.jpg). The footfall design draws on filmed canine gallops. [Greyhound footfall study, section 3.1](https://opus.lib.uts.edu.au/bitstream/10453/134207/4/10.11771464419319858544.pdf) · [Walter and Carrier, ground forces in galloping dogs](https://pubmed.ncbi.nlm.nih.gov/17210958/)

## Open or use the asset

- Open [warhound.blend](source/warhound.blend) for the editable model. To inspect Run in Blender, select the rig, solo its Run track in the Nonlinear Animation editor, and play frames 1–16. Frame 17 repeats the opening pose.
- For Supply Lines, the three files in `godot/` mirror the project root. In a working copy, copy all three, let Godot import them, and instance the [Warhound scene](godot/scenes/models/warhound_model.tscn). It uses the project's existing character animator. Its reference speed is 4 m/s, so the in-place animation matches actor travel at normal playback. If you already use the pilot asset, update both the GLB and the scene wrapper.
- The [GLB](godot/assets/models/units/warhound.glb) includes the texture and all four animation clips. The [leather texture](textures/harness_leather_basecolor.png) and both Blender build scripts are included separately. Rebuild with the stage script from the pilot handoff, using this package's builder. The stage script calls the recipe's export routine to preserve the finer timing of this Run.

## Verification

The final 0.667 s stride covers 2.67 m at its reference speed. An independent 240 Hz check of the exported skin found four distinct touchdowns and two airborne intervals, approximately 92 ms extended and 75 ms gathered. The largest sampled paw dip was 2.15 mm. Checks of all six pairs of legs found zero intersections at 160 sampled poses. The Blender and imported GLB vertex positions agreed within 0.001 mm at 65 sampled phases. [Gait measurements](validation/revised-gait.json) · [Limb clearance](validation/limb-clearances.json)

The resting model has the pilot's geometry, materials, texture and 29-bone rig. To keep the neck and rump from stretching into spikes, 61 coat vertices were rebound to follow the neighboring bones. Those vertices also follow the corrected binding in Rest, Attack and Die. Their animation keys match the original. A clean staged Godot check exercised the shipped scene, animation switching, looping, heading, death cleanup, and both faction paints. The live game checkout and original pilot delivery remain separate. [Body deformation measurements](validation/body-deformation.json) · [Godot import and animation checks](validation/godot.json)
