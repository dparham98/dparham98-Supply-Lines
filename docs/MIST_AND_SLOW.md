# Mist and Slow

Item 14 of the balance handoff (`docs/BALANCE_IMPLEMENTATION_HANDOFF.md` on the balance branch), 2026-11-25. The owner chose the Grail Sentinel as the caster, paying from its healing reserve. Every number is a play-test starting point, in `assets/combat/spell_rules.tres` (`SpellRules`).

## Built on

This branch stacks on two Stage 2 branches:
- the upgrades branch (the Forge), and
- the Sentinel heal branch: the 200-point reserve, refilled only at Keeps.

It needs both merged first.

## Casting

Both spells go on the Grail Sentinel's card:
1. Press **Mist** (Q) or **Slow** (W), then click a point. Shift keeps the command armed.
2. One selected Sentinel that can cast walks to within **20 m** of the point (`cast_range`) and casts at once.

**Cost:** the points come out of the healing reserve (`med_reserve`). So every cast means less healing.

**Greyed out:** a tile is greyed out with the reason when the Sentinel can't cast: not enough reserve, or Slow not yet researched.

## Mist

**Cost:** 40 points.

**Effect:**
- For 8 s, any unit inside an 8 m circle can be seen and targeted only from within 8 m of it, by either side.
- It works through sight, not pathing. Units walk in and out freely.
- **Where it applies** (`MistCloud.hides`):
  - `unit_agent.team_sees`, which every unit uses to pick targets, so it works on maps without fog too;
  - the fog of war's drawing of the other side's units for the viewer (`fog_of_war.gd`).
- Buildings are not hidden.

**Scene:** `scenes/gameplay/mist_cloud.tscn`, a placeholder translucent dome.

## Slow

**Research:** at the Forge (Research.SLOW, `assets/research/slow.tres`): 100 F / 100 I, 60 s. It is the Forge card's third tile, after Arms and Mail.

**Cost:** 25 points.

**Effect:** enemy units within 5 m of the point when it's cast move at 60% of their speed for 5 s (`unit_agent.apply_slow`, `speed_scale`).
- A second Slow on the same unit keeps the stronger factor and the longer time.
- Trains, which move along track, aren't slowed.

**Scene:** `scenes/gameplay/slow_field.tscn` shows the ring for the 5 s.

## Decided here

- **Mist hides everyone:** it hides units of both sides inside it, not only the caster's. A Mist is cover, not a cloak.
- **One caster per click:** only one selected Sentinel casts, so a group doesn't spend all their reserves on one click.
- **Slow research price:** 100 F / 100 I and 60 s. The handoff gave no price.
- **Cast range:** 20 m. The handoff gave none.

## Not done

- **AI:** the Knights AI doesn't cast either spell or research Slow.
- **Art:** the cloud and the ring are placeholders, and the cards borrow other art.

## Check

`tests/mist_slow_test.gd` (headless) covers:
- the Forge's Slow research;
- Mist's cost, and the hiding at 14 m and seeing at 7 m;
- the Mist's end after 8 s;
- Slow needing the research, its cost, and 60% on an enemy 3 m off but not on one 8 m off or a friend;
- Slow wearing off after 5 s;
- the reserve check;
- the card tiles.
