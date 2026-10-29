# UI overhaul plan

Approved by the user on 2026-10-29. This covers how information is shown in the HUD and on the map, plus the crate-shipment logistics redesign. Each phase is its own feature branch and PR, with tests and a human playtest before merge.

## Principles

- Information is never boxed. Only actions (command card tiles, header buttons) look like buttons.
- Show information when it matters: on damage, selection, hover, or Alt to show everything.
- One shared Godot theme (`assets/ui/supply_lines_theme.tres`): a dark slate, teal and amber palette, and Godot's default font.
- Icons are SVGs drawn for the project and kept in the repo (`assets/ui/icons/`).
- The global Build button stays in the header.

## Phases

**A. Theme and command card**
- The shared theme on the HUD and the playtest panel.
- Card tiles with an icon, a label and a corner hotkey badge, in one consistent order.
- Production costs on their own line, with a tooltip saying what is missing when you can't afford something.
- Disabled actions stay visible with a reason.

**B. Selection panels**
- An icon, the name, and a team and state line. Health, fuel and cargo bars with the numbers inside.
- Stats as a plain label and value list (no boxes), with abilities on one muted line.
- Storage, for Depots and Cargo vehicles: one bar split by resource against capacity, with a legend of the amounts. Crated stock is shown lighter once phase E exists.
- Cargo vehicles: tank fuel is a separate bar from cargo, plus a route progress line.
- Trains: the same, plus a tick on the fuel bar for the round trip and an amber warning when fuel is short.
- Depots: a progress bar only while something is in production.

**C. Map status**
- A reusable status scene placed in each actor's scene.
  - Health bar on damage, selection or hover; Alt shows all.
  - Building production progress bar only, with no text.
  - Icons for storage nearly full, under attack, generator paused, exit blocked and mine depleted.
  - A capture ring.
  - A hover card with the name, owner, health and a mini storage bar.
  - "+N resource" when deliveries arrive.
  - Territory and supply rings on selection.
  - A dashed outline for unpaid construction plans.
  - Route lines for the selected vehicle.
  - The carried resource shown on Infantry.

**D. Order feedback and polish**
- Click pings, target highlights, hover rings, alert entries with icons, and a cleaner minimap.

**E. Crate shipments (logistics redesign)** · implemented on `feature/crate-shipments` (CRATE_SHIPMENTS.md)
- **Crates:** each crate holds 25 units of one resource. A Cargo vehicle (100) carries 4 crates and a Train (300) carries 12.
- **Preparing shipments:** done at a Depot or a deployed Cargo vehicle. Crated stock is reserved: production, repair and refuelling can't spend it, but it still counts toward storage.
- **Keep stocked:** a Depot setting that repacks crates as they're collected.
- **Load (L) and Unload (U):** click a Depot or deployed truck. Load takes crates in the order they were packed. Unload unpacks whole crates and keeps any that don't fit.
- **Trips (C):** once, all available, or repeat.
- **Queuing:** Shift+Load and Shift+Unload use the command queue and waypoint markers.
- **Trains:** they load and unload only at Depots with friendly track nearby.
- **Removed:** Route, the per-trip manifest, the Load at / Unload at menus (a Depot list stays for distant Depots), Cancel route (now Stop), Pause/Resume (automatic pausing on capture stays), and the Orders/Delivery route tabs.
- **Tests:** the existing route code stays underneath, driven in whole crates. The older tests that drive the removed Supply panel controls will be rewritten, as approved.
