# Close-defense combat check

From the Supply Lines repository root, run the following with the pinned Godot executable.

```powershell
python Blender/Vehicles/Tank/Astra_Bastion/AutoTurret/validation/run_combat.py --godot C:/Dev/Tools/Godot_v4.7.2-stable_win64_console.exe
```

The runner stages First Contact, its ordinary unit logic and the opt-in Bastion actor in a temporary game copy. Godot runs at a fixed 60 Hz. The primary cannon receives an attack order against a unit 24 world metres away. A second hostile enters at 8 m. Real damage, primary shells and the secondary muzzle transform establish that each gun can engage its own target. The fixture measures the separate bullet mesh, follows its position across frames and checks that damage arrives when it reaches the target. A unit that moves off the captured shot line or becomes friendly while the bullet is in flight escapes the hit.

The fixture also covers a closer friendly and neutral, a hostile 10.2 m away, a hull bearing change, a freed target, range exit and reentry, pause and the last round completing its flight after the launcher dies.

Three further runs put the variant mesh in the stock actor's model slot in the temporary game. The unchanged firing, track and death suites check the inherited tank rig independently of the close-defense component. [Recorded results](combat.json)
