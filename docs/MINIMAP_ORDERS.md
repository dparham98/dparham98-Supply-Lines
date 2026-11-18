# Minimap orders

The minimap can give orders as well as move the camera.

| Click on the minimap | With | Does |
| --- | --- | --- |
| Left-click | nothing waiting | Moves the camera there, as before. Selection is kept. |
| Right-click | units selected | Gives the order a right-click on the map would give at that point: move, attack a hostile, gather, return cargo, repair, capture and the rest (`issue_order` in `skirmish.gd`). Shift queues. By your own Depot it moves there; it is a Return only for units carrying cargo. |
| Right-click | nothing selected | Nothing. |
| Right-click | a command waiting | Cancels it, as on the map. |
| Left-click | Move, Attack, Gather, Repair, Capture, Deploy, Load or Unload waiting | Gives that command at the point or marker, as a left-click on the map would (`issue_card_order`). Attack on open ground is attack-move. Attack never forces fire on your own units, buildings or mines from the minimap: by them it attack-moves too. Shift queues and keeps the command waiting. |
| Left-click | Pin waiting | Picks a pulsing stop, as before; away from every stop it moves the camera. |

## How it works

`tactical_minimap.gd` turns the click into a world point and calls `issue_map_order` on the game. That passes a `MapPick` (the point and a pick radius) to `issue_order` or `issue_card_order` in place of the pointer's screen position. `ground_at` returns its point instead of casting from the camera, and `pick_target` chooses the marker nearest it on the ground instead of the nearest model under the pointer. The map's own order rules then run, so the minimap and the map cannot drift apart. They differ only where a minimap click lands near markers rather than on them: no forced fire on friendlies, and no Return order for a unit carrying nothing.

The pick radius is 4 minimap pixels, `ORDER_PICK_RADIUS`, about 10 m on the 500 m map, taken by the coarser axis if the minimap is not square. It is measured to each node's model bounds, so a large building is picked anywhere on its footprint. A click that close to a hostile, resource, Depot or other marker targets it; anywhere else is open ground.

Building placement (plans, rail, Depots, Generators, production buildings) is not done from the minimap. While one is armed, a left-click on the minimap still moves the camera and a right-click cancels.

## Shift held before the command key

The playtest of 2026-11-17 found that queueing on the minimap and its Attack command did nothing. The cause was the keyboard, not the minimap: holding Shift and then pressing A (or M, or any command key) did not arm the command, because a button's shortcut matches only the exact key with no Shift. `_unhandled_key_input` in `skirmish_hud.gd` now passes such a key on without Shift when it is the shortcut of a visible, enabled button, so Shift+A arms Attack and the Shift-clicks that follow queue. `tests/minimap_orders_test.gd` sends a real Shift+A and two Shift-clicks and checks both attack-moves are queued.

## Limits

- Markers are a few pixels across, and units in a group overlap, so a right-click near a crowd targets whichever marker is nearest.
- The minimap shows everything, with no fog of war, so hostiles can be targeted anywhere on the map.
- `tests/minimap_orders_test.gd` covers the orders above with synthetic clicks sent to the minimap. Nobody has tried it with a real mouse.
