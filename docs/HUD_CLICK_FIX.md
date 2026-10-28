# HUD click fix

The HUD previously hid every command button, supply panel and build panel at the start of each process frame, then showed the current selection's controls again. A normal mouse gesture spans frames; hiding the button cancels its pressed state before release. Earlier HUD tests emitted button signals directly and did not detect this.

The HUD now calculates desired buttons and applies their final visibility once per frame. Build, supply and main-card panels are each assigned only their final visibility. Selection-sensitive commands remain unchanged, and visible controls stay present during a mouse gesture.

Validation: tests/hud_click_test.gd failed before the fix on the first Depot production click, then passed headlessly and in a rendered Godot Vulkan session. The test sends mouse motion and press/release events through Viewport.push_input with five process frames between press and release. It does not emit button signals. It checks all three Depot production buttons, infantry Build, generator and Depot construction choices, actual world-placement clicks, Back, Move and cargo assign/pause/resume/cancel. Generator processing is stopped before the Depot payment assertion to isolate live income from construction costs. The existing bottom_hud_test.gd, skirmish_test.gd and supply_test.gd also passed after the fix.

This is automated GUI event testing, not physical mouse or live editor input. Rendered run output is in the chat workspace hud_click_runtime.log and hud_click_runtime_errors.log. Restart the running scene to load the corrected script. Select infantry → Build → choose a local payer and building → click valid land. Select a friendly Depot to print units; existing local resource costs and queue limits still apply. The 500-iron testing grant remains enabled.

Changed in this fix: scripts/gameplay/skirmish_hud.gd; tests/hud_click_test.gd and generated .uid; docs/HUD_CLICK_FIX.md; docs/BOTTOM_HUD_VALIDATION.md; docs/BOTTOM_HUD_CHANGED.txt. Before-fix HUD script is backed up in the chat workspace as hud_click_before.gd.
