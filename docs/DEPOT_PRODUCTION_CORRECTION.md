# Depot production correction

Latest user instruction supersedes the earlier repeatable-Infantry decision. Depot HUD no longer offers Infantry production and its old request API rejects without payment or queue changes. Barracks retains repeatable Infantry production. Existing once-only establishment grants for constructed/truck-deployed Depots remain; blocked exits retry and capture cancels pending grants, as previously documented. Authored starting scenes retain their authored infantry without an extra duplicate grant.

Skirmish recovery considers the ability to establish a new Depot and obtain its one Infantry, rather than the removed repeatable Depot Infantry job. The gather/print/fight regression now pays to construct a Barracks and produces its infantry there. Depot/supply/HUD queue regressions use Cargo Vehicles at the same existing 100 E / 20 I cost.

This correction does not yet implement coal, finite-capacity storage, universal forestry, shared buildable mines, dropped materials, mobile supply deployment, or generator fuel. See ECONOMY_PLAN.md for the proposed balance sheet and the remaining decisions.
