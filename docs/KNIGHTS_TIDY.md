# Knights tidy-up

Item 2 of `docs/BALANCE_IMPLEMENTATION_HANDOFF.md` (2026-11-23).

- **No Chapterhouse speed setting.** Extra production speed is charged as a share of the unit's energy price, and Knights units cost no energy, so the Chapterhouse's 1x to 4x setting was free. `assets/buildings/chapterhouse.tres` now has `max_power = 1.0`, and the HUD shows the production-speed panel only for a building whose `max_power` is above 1. Barracks and Tank Factory keep 1x to 4x.
- **Each faction's own Build page.** The Cyborgs see Depot, Generator, Barracks, Tank Factory, Temple of Science and track; the Knights see Keep and Chapterhouse. Iron and Coal Mines are shown to both. The lists are `CYBORG_BUILDINGS` and `KNIGHT_BUILDINGS` in `scripts/gameplay/skirmish_hud.gd`. In a match started from the main menu the player's faction setting decides. In a scene run straight from the editor or a test, a player who holds a Depot that is not a Keep, or has no Knights presence, builds as the Cyborgs; one with a Keep or Knights units builds as the Knights. A player with both sees both pages' buildings. Hidden tiles' hotkeys do nothing, as before.
- **AI Drones stay with the army.** The Drone is unarmed and outruns everything, so the Cyborg AI used to send it ahead of its wave to die. `EnemyPlayer._escort_drones` now moves each Drone back over the centre of the ground units it goes with (its wave's, or else the rest of the army's) whenever it strays more than `drone_escort_radius` (6 m, an export on `scripts/ai/enemy_player.gd`). It runs every AI think, after the wave's or the defence's orders.

**Check.** `tests/knights_tidy_test.gd` (headless): the Chapterhouse stays at 1x when set to 4x, a Round Table Marine takes its listed build time, and no speed panel shows; Barracks and Tank Factory keep theirs; the Build page lists for a Knights scene, a Cyborg scene and a configured Knights match; and on Two Lakes a Drone in a moving wave of two Tanks and two Deforesters stays within 15 m of the wave's centre over 20 s, the wave having moved more than 20 m.

Not checked by a person: how the Build pages look, and whether the Drone's escort reads well in an AI match.
