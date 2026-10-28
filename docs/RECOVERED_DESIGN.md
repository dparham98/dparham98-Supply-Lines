# Recovered design and prototype decisions

Reviewed the available project conversation excerpts again on October 15, 2026. The chat reader exposes only five recent user messages for RTS resource tech tree and four for Cyborg character template, with no older-page cursor. Synced sources contains no additional design files. This is not a complete recovery of the original discussions.

## Supported by the available user messages

| Topic | Recovered description |
| --- | --- |
| World | Everyone is a cyborg. |
| Depot | A building with 3D-printing capabilities; its earlier capability discussion is unavailable. |
| Infantry | German appearance, black trench coat, engineering skill, chainsaw left hand, gun in right hand; simplified for RTS. |
| Scout | Female cyborg with rollerblades and a gun; another reference brief specifies a shotgun and front/side/back model views. |
| Tank | Tank unit with flat front/top/side reference views requested. |
| Map | User identified water, desert, forest, grass, mountains and resource deposits; iron was tentative. |

References: [RTS resource tech tree](chatgpt-conversation://68801789-c024-800d-9f1f-35be6b18573d), [Cyborg character template](chatgpt-conversation://689eae8f-f92c-8320-b335-36402fed2c4f). The current user recalls infantry both gathering resources and attacking at range; the playable scenario implements that role.

No additional named building or separate worker class, exact resource list, production costs, tech prerequisites, extraction rates, logistics rules or victory rules were recoverable. Headquarters existed in the old local code; that does not establish its historical design relationship with Depot.

## Deliberate temporary rules

First Contact uses one generic Ore resource and a Depot as drop-off and infantry printer. A starting infantry gathers and fights. One printed infantry costs 20 delivered Ore and takes 3 seconds; queues hold 3. Capacity is 10 Ore; harvests yield 5 every 0.6 seconds. Player infantry has 100 HP, 12 range, 16 damage and a 0.7-second shot interval. A stationary hostile has 120 HP, 10 range, 6 damage and a 1.2-second interval. Victory requires a delivery, a completed print and an enemy kill. These values are Inspector settings or scenario rules, not recovered design specifications.

The marked deposit sits on an existing red Ore area. It has 500 extractable Ore; other baked deposits remain visual scenery. Depletion does not change terrain navigation. There is no forestry, new building construction, tech tree, economy network, multiplayer, save/load, combat line-of-sight or animated model rig. The new cyborg silhouettes are editable native placeholder scenes, not the separate Blender infantry export.
