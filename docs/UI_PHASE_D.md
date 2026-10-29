# UI phase D: order feedback and polish

Phase D of `UI_OVERHAUL_PLAN.md`, on branch `feature/ui-feedback-polish` from main `c43ac42`. All map marks are still drawn by `MapOverlay` (phase C).

## Changes

- **Order pings:**
  - Every order through `skirmish.give_order` emits `order_given(kind, point, target, queued)`. A group order makes one ping, not one per unit.
  - Ground orders draw an expanding ring in the order's colour: move teal, attack red, gather green, deliver and repair amber, capture white. Queued orders lack the centre dot.
  - Orders on a target draw corner brackets around it in the same colour for 0.8 s.
- **Hover ring:** an ellipse under the hovered unit, white for friendly and red for enemy.
- **Plan footprints:** unpaid construction plans get a dashed outline of their footprint. This completes the item deferred from phase C.
- **Hover card:** now stays above the bottom HUD.
- **Alert feed:** `alert(text, at, key, kind)` takes a kind. Feed entries show an icon in that kind's colour: attack (red crosshair), lost (red cross), fuel (amber pump).
- **Minimap:**
  - Markers use the overlay's team and resource colours with dark edges. Buildings are squares, units are dots, resources are diamonds.
  - Recent alerts pulse where they happened for 6 s.
  - The map has a frame.

## Validation

- `tests/feedback_polish_test.gd` (headless) checks:
  - one ping for a two-unit group move;
  - the queued flag on Shift orders;
  - an attack ping targeting the hostile;
  - ping expiry;
  - a closed five-point plan outline;
  - feed icons and colour by alert kind.
- `tests/feedback_polish_runtime_check.gd` (rendered) uses a real selection click, two real right-clicks (one plain, one Shift) and a Shift-right-click attack on a hostile, then hovers over it. Its screenshot is `order_feedback`.
- An earlier version merged pings up to 0.1 s apart, which also swallowed separate quick clicks. Pings now merge only when they come from the same instant, which is what a group order produces.
