# Builders start when they touch the site

From the playtest of main at 9eaed10 (2026-11-15).

## Before

An Infantry sent to build walked to the standing cell nearest to it inside a circle round the plan's centre. It kept walking until it reached that cell, even after it was already in reach. A builder coming from an odd angle therefore walked round the site for a few paces before it started.

## Now

A builder starts work as soon as it touches the footprint, from whichever side it comes. It then stops walking and stays where it is while it works.

- **Touching** means within 1 m of the footprint's edge (`TOUCH` in `interaction_approach.gd`), which covers a cell beside the footprint, straight or diagonal.
- **Route:** `touch_path` routes the builder to the nearest open cell beside the footprint.
- **Builders still never stand on the footprint.** One that is on it steps off first.
- **When no cell beside the footprint can be reached,** the builder falls back to the old rule: it works from anywhere within the old reach of the plan's centre, once its walk ends.

## Tests

`tests/builder_touch_test.gd` (headless, balanced map) sends builders at a Barracks plan from two directions: diagonally at a corner, and at the middle of a side. For each one it checks that the builder:

- starts work touching the footprint;
- did not walk round the site;
- stopped its route;
- keeps working where it stands.
