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

**Scene:** `scenes/gameplay/mist_cloud.tscn`, a low rolling holy mist (see Art).

## Slow

**Research:** at the Forge (Research.SLOW, `assets/research/slow.tres`): 100 F / 100 I, 60 s. It is the Forge card's third tile, after Arms and Mail.

**Cost:** 25 points.

**Effect:** enemy units within 5 m of the point when it's cast move at 60% of their speed for 5 s (`unit_agent.apply_slow`, `speed_scale`).
- A second Slow on the same unit keeps the stronger factor and the longer time.
- Trains, which move along track, aren't slowed.

**Scene:** `scenes/gameplay/slow_field.tscn` shows a ground sigil for the 5 s (see Art).

## Decided here

- **Mist hides everyone:** it hides units of both sides inside it, not only the caster's. A Mist is cover, not a cloak.
- **One caster per click:** only one selected Sentinel casts, so a group doesn't spend all their reserves on one click.
- **Slow research price:** 100 F / 100 I and 60 s. The handoff gave no price.
- **Cast range:** 20 m. The handoff gave none.

## Not done

- **AI:** the Knights AI doesn't cast either spell or research Slow.
- **Art:** no per-unit mark on a slowed unit (`speed_scale() < 1`); the sigil on the ground is the only sign.

## Check

`tests/mist_slow_test.gd` (headless) covers:
- the Forge's Slow research;
- Mist's cost, and the hiding at 14 m and seeing at 7 m;
- the Mist's end after 8 s;
- Slow needing the research, its cost, and 60% on an enemy 3 m off but not on one 8 m off or a friend;
- Slow wearing off after 5 s;
- the reserve check;
- the card tiles.

## Art

Added on 2026-11-25. Gameplay scripts only set numbers; the looks are authored scenes that read them.

- **The cast** (`scenes/models/grail_sentinel_model.tscn`, `scripts/components/spell_animator.gd`, which extends `character_animator.gd`). `unit_agent._spell_order` calls `play_cast(kind)` on the model when it casts.
  - The Sentinel sweeps its right arm up overhead in 0.22 s, holds to 0.52 s and settles by 0.9 s. The clip is `Cast` in `assets/models/units/grail_sentinel_cast.tres`, added to the rig's player as `spells/Cast`. The rig has no Blender source, so `scripts/tools/build_sentinel_cast.gd` keys the clip from the bones' rests. Change the poses there and re-run it.
  - A burst of light rides on the right hand: a flash as the arm reaches the top, a shaft of light, a spreading halo, falling motes and a light. Mist's burst (`scenes/models/sentinel_cast_mist_fx.tscn`) is pale gold; Slow's (`sentinel_cast_slow_fx.tscn`) is blue. Both run `burst_effect.gd` once and free themselves.
  - The spell itself lands on the first frame, as before; the gesture is only the look.
- **Mist** (`mist_cloud.tscn`). Three stacked discs at 0.3, 0.9 and 1.6 m draw a low rolling cloud with `assets/shaders/holy_mist.gdshader`: pale grey-white noise that swirls slowly about the centre, a frayed rim and faint gold motes. It is at most about a third opaque per layer, so the ground and the units in it still show from the RTS camera.
- **Slow** (`slow_field.tscn`). One disc at 0.12 m draws a ground sigil with `assets/shaders/slow_sigil.gdshader`: a gold double ring with runes, a turning blue eight-pointed star, and a faint blue wash. It pulses gently. The field now has a `radius` (set from `slow_radius`) as well as `seconds`.
- **Timing** (`scripts/components/spell_look.gd`, on each scene's Visuals). It reads the spell's `seconds` and `radius` each frame:
  - Mist billows in over 0.5 s, growing from 55% of its radius, and thins over its last 1 s. The noise breaks up before the layer fades.
  - The sigil draws in from the rim over 0.35 s and fades over its last 0.8 s.
- **Cards** (`Blender/UI/SpellCards/render_spell_cards.py`, framed by `render_hud_images.gd -- spell_cards`):
  - `sl_mist.png`: a gold grail over a swirl of mist with gold motes.
  - `sl_slow.png`: the sigil with an hourglass standing in it.
  - `sl_research_slow.png`: the hourglass rising from an open book over a ring of the sigil. `show_upgrade_building` shows plain research as `research_<id>`.
- **Rendered check:** `tests/mist_slow_runtime_check.gd` shows the cast, the Mist over a squad and in its last second, and the Slow sigil under enemy infantry.
