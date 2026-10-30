# Independent audit fixes

Follow-up to the independent audit of main `213c0d226d6f0d67d3c24a3cf730ffdb9069fb34` (PRs #14 and #15).

## Crate transport and yards

- A crate picked up by another truck becomes a ground pickup at its saved location. Freed references are normalized before typed calls, including queued orders.
- A destroyed Depot or unavailable deployed supply vehicle cancels its active shipment and retains cargo. Queued endpoint orders are skipped if the endpoint disappears; they do not become accidental ground drops. Repeated trips stop returning to a lost endpoint.
- Packing uses the same radius as yard display, pickup and Refill: 10 units for Depots and 4 for deployed Cargo vehicles. A full/blocked yard keeps its loose stock.
- Explicitly unpacking one full crate updates the Refill target to the remaining count, without subtracting the removed crate twice.

`crate_lifecycle_test.gd` covers competing pickups before/after deferred deletion, queued pickup and endpoint destruction, retained cargo, full yards for both owner types, and unpack/refill counts. Existing crate accounting and trip suites remain applicable.

## Mobile supply test

The historical `mobile_supply_runtime_check` pile-gather failure came from clicking above the pile's mesh. Its click now uses the visible mesh's actual centre. Gameplay selection and harvesting rules are unchanged.

## Terrain baking

The baker now supplies complete transform/color buffers explicitly instead of relying on rendering-backend instance setters to preserve serialized data. Rebuild checks buffer sizes before overwriting saved scenery. The scene-setup test checks buffer presence, duplication and save/reload, and restores the committed scenery bytes.

The independent data comparison found identical transforms across all five batches against the earlier GPU compatibility bake. Color components differ by less than 0.001; the new CPU data retains full float precision. This does not certify visual equivalence in the Forward Plus editor. No generated scenery is committed by this change.

## Acceptance still required

Headless checks do not certify native hover, visuals, input feel or performance. Human Windows/Forward Plus playtesting and editor rebuild acceptance remain outstanding. Forest deployment still requires an empty buildable 8 × 8 footprint; this change introduces no forest-clearing or crate/building overlap policy.
