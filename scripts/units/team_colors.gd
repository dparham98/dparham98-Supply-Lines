extends RefCounted
## One colour per side, shared by the map overlay, the minimap and the team markers under units
## (docs/TEAM_MARKERS.md).
const COLORS := {"player": Color(0.37,0.82,0.54), "enemy": Color(0.89,0.35,0.31), "neutral": Color(0.6,0.65,0.68)}
static func of(team: String) -> Color:
	return COLORS.get(team,COLORS["neutral"])
