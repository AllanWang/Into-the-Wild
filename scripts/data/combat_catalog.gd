class_name CombatCatalog
extends RefCounted

## Central static catalog for Symmetric Weapons, Slottable Weapon Shards,
## Q/E Abilities (including Leech/Heal), R Artifacts, and Core Stat Upgrades.

enum WeaponId {
	NONE = 0,
	PULSE_REPEATER = 1,
	SCATTER_PRISM = 2,
	ARCANE_CHAKRAM = 3,
	RAIL_LANCE = 4,
	NOVA_MORTAR = 5
}

enum AbilityId {
	NONE = 0,
	AEGIS_BARRIER = 1,
	STARFALL_STRIKE = 2,
	FROST_NOVA = 3,
	TEMPO_SURGE = 4,
	SOUL_SIPHON = 5
}

enum ArtifactId {
	NONE = 0,
	SOLAR_CONVERGENCE = 1,
	CHRONOSPHERE = 2,
	SEEKER_BARRAGE = 3,
	SANGUINE_HARVEST = 4
}

enum ShardId {
	NONE = 0,
	SHARD_VENOM = 1,
	SHARD_STORM = 2,
	SHARD_CINDER = 3,
	SHARD_RIME = 4,
	SHARD_KEEN = 5,
	SHARD_TEMPO = 6
}

enum TraitId {
	STAT_AD = 1,
	STAT_AP = 2,
	STAT_HP = 3,
	STAT_ATK_SPD = 4,
	STAT_HASTE = 5,
	STAT_MOVE_SPD = 6,
	ELEM_POISON = 10,
	ELEM_SHOCK = 11,
	ELEM_BURN = 12,
	ELEM_FROST = 13
}

enum GlyphKind {
	EMPTY = 0,
	BOLT = 1,
	SCATTER = 2,
	CHAKRAM = 3,
	LANCE = 4,
	MORTAR = 5,
	SHIELD = 6,
	STAR = 7,
	FROST = 8,
	SURGE = 9,
	SOLAR = 10,
	CHRONO = 11,
	SEEKER = 12,
	SIPHON = 13,
	HARVEST = 14
}

static var _weapons: Dictionary = {}
static var _abilities: Dictionary = {}
static var _artifacts: Dictionary = {}
static var _shards: Dictionary = {}
static var _traits: Dictionary = {}


static func _ensure_init() -> void:
	if not _weapons.is_empty():
		return

	_weapons[WeaponId.PULSE_REPEATER] = {
		"id": WeaponId.PULSE_REPEATER,
		"name": "Pulse Repeater",
		"subtitle": "Rapid Bolt Weapon",
		"desc": "Fires crisp high-velocity bolts (1.0x AD). Great with Attack Speed, Venom & Storm Shards.",
		"is_cooldown": false,
		"interval": 0.24,
		"cooldown": 0.0,
		"ad_ratio": 1.0,
		"ap_ratio": 0.0,
		"proc_coeff": 1.0,
		"speed": 25.0,
		"range": 12.5,
		"pellets": 1,
		"spread_deg": 0.0,
		"aoe_radius": 0.0,
		"glyph": GlyphKind.BOLT,
		"color": Color(1.0, 0.88, 0.42, 1.0)
	}

	_weapons[WeaponId.SCATTER_PRISM] = {
		"id": WeaponId.SCATTER_PRISM,
		"name": "Scatter Prism",
		"subtitle": "5-Shard Spread Weapon",
		"desc": "Blasts a 5-bolt close/mid fan (5 x 0.42x AD). Rapidly stacks Venom & Rime Shards.",
		"is_cooldown": false,
		"interval": 0.54,
		"cooldown": 0.0,
		"ad_ratio": 0.42,
		"ap_ratio": 0.0,
		"proc_coeff": 0.45,
		"speed": 23.0,
		"range": 7.8,
		"pellets": 5,
		"spread_deg": 24.0,
		"aoe_radius": 0.0,
		"glyph": GlyphKind.SCATTER,
		"color": Color(1.0, 0.56, 0.28, 1.0)
	}

	_weapons[WeaponId.ARCANE_CHAKRAM] = {
		"id": WeaponId.ARCANE_CHAKRAM,
		"name": "Arcane Chakram",
		"subtitle": "Returning Hybrid Disc",
		"desc": "Throws a piercing disc (0.65x AD + 0.60x AP) that curves back through enemies.",
		"is_cooldown": false,
		"interval": 0.48,
		"cooldown": 0.0,
		"ad_ratio": 0.65,
		"ap_ratio": 0.60,
		"proc_coeff": 0.75,
		"speed": 19.5,
		"range": 9.2,
		"pellets": 1,
		"spread_deg": 0.0,
		"aoe_radius": 0.0,
		"glyph": GlyphKind.CHAKRAM,
		"color": Color(0.62, 0.82, 1.0, 1.0)
	}

	_weapons[WeaponId.RAIL_LANCE] = {
		"id": WeaponId.RAIL_LANCE,
		"name": "Rail Lance",
		"subtitle": "Piercing Line Weapon (2.6s CD)",
		"desc": "High-impact piercing lance (2.4x AD) through all foes in a line. Huge Cinder Shard ignites.",
		"is_cooldown": true,
		"interval": 0.25,
		"cooldown": 2.6,
		"ad_ratio": 2.4,
		"ap_ratio": 0.0,
		"proc_coeff": 1.0,
		"speed": 38.0,
		"range": 16.0,
		"pellets": 1,
		"spread_deg": 0.0,
		"aoe_radius": 0.0,
		"glyph": GlyphKind.LANCE,
		"color": Color(1.0, 0.34, 0.40, 1.0)
	}

	_weapons[WeaponId.NOVA_MORTAR] = {
		"id": WeaponId.NOVA_MORTAR,
		"name": "Nova Mortar",
		"subtitle": "Arcane AoE Weapon (3.2s CD)",
		"desc": "Detonates a 2.8m blast at the cursor (1.0x AD + 2.2x AP). Scales with Ability Haste.",
		"is_cooldown": true,
		"interval": 0.25,
		"cooldown": 3.2,
		"ad_ratio": 1.0,
		"ap_ratio": 2.2,
		"proc_coeff": 1.0,
		"speed": 0.0,
		"range": 13.0,
		"pellets": 1,
		"spread_deg": 0.0,
		"aoe_radius": 2.8,
		"glyph": GlyphKind.MORTAR,
		"color": Color(0.82, 0.50, 1.0, 1.0)
	}

	_abilities[AbilityId.AEGIS_BARRIER] = {
		"id": AbilityId.AEGIS_BARRIER,
		"name": "Aegis Barrier",
		"subtitle": "Defensive Ability (10s CD)",
		"desc": "Grants 25 + 2.0x AP temporary Shield for 6s and emits a protective ward.",
		"cooldown": 10.0,
		"glyph": GlyphKind.SHIELD,
		"color": Color(0.38, 0.88, 1.0, 1.0)
	}

	_abilities[AbilityId.STARFALL_STRIKE] = {
		"id": AbilityId.STARFALL_STRIKE,
		"name": "Starfall Strike",
		"subtitle": "Burst AoE Ability (8s CD)",
		"desc": "Calls down a 3.0m flare at cursor after 0.35s for 30 + 2.5x AP damage + elemental shards.",
		"cooldown": 8.0,
		"glyph": GlyphKind.STAR,
		"color": Color(1.0, 0.84, 0.42, 1.0)
	}

	_abilities[AbilityId.FROST_NOVA] = {
		"id": AbilityId.FROST_NOVA,
		"name": "Frost Nova",
		"subtitle": "Control Ability (9s CD)",
		"desc": "Creates a 3.8m stasis field at cursor for 3.5s, dealing 18 + 1.5x AP and slowing by 55%.",
		"cooldown": 9.0,
		"glyph": GlyphKind.FROST,
		"color": Color(0.52, 0.92, 1.0, 1.0)
	}

	_abilities[AbilityId.TEMPO_SURGE] = {
		"id": AbilityId.TEMPO_SURGE,
		"name": "Tempo Surge",
		"subtitle": "Overdrive Ability (12s CD)",
		"desc": "Surges +45% Attack Speed and +25% Move Speed for 4.5s.",
		"cooldown": 12.0,
		"glyph": GlyphKind.SURGE,
		"color": Color(0.45, 1.0, 0.62, 1.0)
	}

	_abilities[AbilityId.SOUL_SIPHON] = {
		"id": AbilityId.SOUL_SIPHON,
		"name": "Soul Siphon",
		"subtitle": "Leech AoE Ability (10s CD)",
		"desc": "Detonates a 3.6m siphon at cursor for 24 + 2.0x AP damage and heals 35% of damage dealt.",
		"cooldown": 10.0,
		"glyph": GlyphKind.SIPHON,
		"color": Color(0.96, 0.36, 0.58, 1.0)
	}

	_artifacts[ArtifactId.SOLAR_CONVERGENCE] = {
		"id": ArtifactId.SOLAR_CONVERGENCE,
		"name": "Solar Convergence",
		"subtitle": "Active Artifact [R] (26s CD)",
		"desc": "Channels a 3-pulse orbital pillar at cursor (3.8m), dealing 45 + 3.5x AP per pulse.",
		"cooldown": 26.0,
		"glyph": GlyphKind.SOLAR,
		"color": Color(1.0, 0.78, 0.32, 1.0)
	}

	_artifacts[ArtifactId.CHRONOSPHERE] = {
		"id": ArtifactId.CHRONOSPHERE,
		"name": "Chronosphere",
		"subtitle": "Active Artifact [R] (28s CD)",
		"desc": "Expands a 7.5m time-dilation dome (80% enemy slow for 5s) and grants 40 + 1.5x AP Shield.",
		"cooldown": 28.0,
		"glyph": GlyphKind.CHRONO,
		"color": Color(0.48, 0.94, 1.0, 1.0)
	}

	_artifacts[ArtifactId.SEEKER_BARRAGE] = {
		"id": ArtifactId.SEEKER_BARRAGE,
		"name": "Seeker Barrage",
		"subtitle": "Active Artifact [R] (24s CD)",
		"desc": "Unleashes 10 homing missiles across nearby foes for 14 + 0.8x AD + 0.8x AP each.",
		"cooldown": 24.0,
		"glyph": GlyphKind.SEEKER,
		"color": Color(1.0, 0.44, 0.62, 1.0)
	}

	_artifacts[ArtifactId.SANGUINE_HARVEST] = {
		"id": ArtifactId.SANGUINE_HARVEST,
		"name": "Sanguine Harvest",
		"subtitle": "Leech Artifact [R] (26s CD)",
		"desc": "Channels a 3-pulse 4.0m crimson vortex (32 + 2.5x AP/pulse), healing 25% of damage dealt.",
		"cooldown": 26.0,
		"glyph": GlyphKind.HARVEST,
		"color": Color(0.96, 0.28, 0.44, 1.0)
	}

	_shards[ShardId.SHARD_VENOM] = {
		"id": ShardId.SHARD_VENOM,
		"name": "Venom Shard",
		"subtitle": "Weapon Shard — Poison",
		"desc": "Slots into LMB or RMB: hits apply stacking Poison DoT (AD/AP scaled). Hold [Alt] to move.",
		"color": Color(0.36, 0.96, 0.48, 1.0)
	}
	_shards[ShardId.SHARD_STORM] = {
		"id": ShardId.SHARD_STORM,
		"name": "Storm Shard",
		"subtitle": "Weapon Shard — Shock",
		"desc": "Slots into LMB or RMB: chance on hit to arc AP Chain Lightning to 3 foes. Hold [Alt] to move.",
		"color": Color(0.42, 0.88, 1.0, 1.0)
	}
	_shards[ShardId.SHARD_CINDER] = {
		"id": ShardId.SHARD_CINDER,
		"name": "Cinder Shard",
		"subtitle": "Weapon Shard — Burn",
		"desc": "Slots into LMB or RMB: ignites targets for % of triggering hit damage over 3s. Hold [Alt] to move.",
		"color": Color(1.0, 0.48, 0.18, 1.0)
	}
	_shards[ShardId.SHARD_RIME] = {
		"id": ShardId.SHARD_RIME,
		"name": "Rime Shard",
		"subtitle": "Weapon Shard — Frost",
		"desc": "Slots into LMB or RMB: chills enemies on hit, slowing move speed for 2.5s. Hold [Alt] to move.",
		"color": Color(0.62, 0.95, 1.0, 1.0)
	}
	_shards[ShardId.SHARD_KEEN] = {
		"id": ShardId.SHARD_KEEN,
		"name": "Keen Shard",
		"subtitle": "Weapon Shard — Force",
		"desc": "Slots into LMB or RMB: +28% direct hit damage on the attached weapon. Hold [Alt] to move.",
		"color": Color(1.0, 0.80, 0.32, 1.0)
	}
	_shards[ShardId.SHARD_TEMPO] = {
		"id": ShardId.SHARD_TEMPO,
		"name": "Tempo Shard",
		"subtitle": "Weapon Shard — Cadence",
		"desc": "Slots into LMB or RMB: +25% fire rate (or -20% cooldown) on that weapon. Hold [Alt] to move.",
		"color": Color(0.84, 0.54, 1.0, 1.0)
	}

	_traits[TraitId.STAT_AD] = {
		"id": TraitId.STAT_AD,
		"name": "Keen Edge",
		"subtitle": "Stat Trait",
		"desc": "+4 Attack Damage (AD) to all weapon scaling.",
		"color": Color(1.0, 0.56, 0.36, 1.0)
	}
	_traits[TraitId.STAT_AP] = {
		"id": TraitId.STAT_AP,
		"name": "Arcane Focus",
		"subtitle": "Stat Trait",
		"desc": "+6 Ability Power (AP) to abilities, shields, and arcane weapons.",
		"color": Color(0.68, 0.56, 1.0, 1.0)
	}
	_traits[TraitId.STAT_HP] = {
		"id": TraitId.STAT_HP,
		"name": "Vitality Core",
		"subtitle": "Stat Trait",
		"desc": "+25 Max Health and restores 25 Health immediately.",
		"color": Color(0.95, 0.34, 0.34, 1.0)
	}
	_traits[TraitId.STAT_ATK_SPD] = {
		"id": TraitId.STAT_ATK_SPD,
		"name": "Rapid Trigger",
		"subtitle": "Stat Trait",
		"desc": "+22% Attack Speed across all sustained weapons.",
		"color": Color(1.0, 0.88, 0.42, 1.0)
	}
	_traits[TraitId.STAT_HASTE] = {
		"id": TraitId.STAT_HASTE,
		"name": "Flow Resonance",
		"subtitle": "Stat Trait",
		"desc": "+25 Ability Haste (reduces Q, E, R, and cooldown weapon timers).",
		"color": Color(0.45, 0.90, 1.0, 1.0)
	}
	_traits[TraitId.STAT_MOVE_SPD] = {
		"id": TraitId.STAT_MOVE_SPD,
		"name": "Windstride",
		"subtitle": "Stat Trait",
		"desc": "+12% Movement & Dash Speed.",
		"color": Color(0.42, 1.0, 0.62, 1.0)
	}
	_traits[TraitId.ELEM_POISON] = _shards[ShardId.SHARD_VENOM]
	_traits[TraitId.ELEM_SHOCK] = _shards[ShardId.SHARD_STORM]
	_traits[TraitId.ELEM_BURN] = _shards[ShardId.SHARD_CINDER]
	_traits[TraitId.ELEM_FROST] = _shards[ShardId.SHARD_RIME]


static func get_weapon(id: int) -> Dictionary:
	_ensure_init()
	return _weapons.get(id, {})


static func get_ability(id: int) -> Dictionary:
	_ensure_init()
	return _abilities.get(id, {})


static func get_artifact(id: int) -> Dictionary:
	_ensure_init()
	return _artifacts.get(id, {})


static func get_shard(id: int) -> Dictionary:
	_ensure_init()
	return _shards.get(id, {})


static func get_trait(id: int) -> Dictionary:
	_ensure_init()
	return _traits.get(id, {})


static func get_all_weapon_ids() -> Array[int]:
	return [
		WeaponId.PULSE_REPEATER,
		WeaponId.SCATTER_PRISM,
		WeaponId.ARCANE_CHAKRAM,
		WeaponId.RAIL_LANCE,
		WeaponId.NOVA_MORTAR
	]


static func get_all_ability_ids() -> Array[int]:
	return [
		AbilityId.AEGIS_BARRIER,
		AbilityId.STARFALL_STRIKE,
		AbilityId.FROST_NOVA,
		AbilityId.TEMPO_SURGE,
		AbilityId.SOUL_SIPHON
	]


static func get_all_artifact_ids() -> Array[int]:
	return [
		ArtifactId.SOLAR_CONVERGENCE,
		ArtifactId.CHRONOSPHERE,
		ArtifactId.SEEKER_BARRAGE,
		ArtifactId.SANGUINE_HARVEST
	]


static func get_all_shard_ids() -> Array[int]:
	return [
		ShardId.SHARD_VENOM,
		ShardId.SHARD_STORM,
		ShardId.SHARD_CINDER,
		ShardId.SHARD_RIME,
		ShardId.SHARD_KEEN,
		ShardId.SHARD_TEMPO
	]


static func get_all_stat_trait_ids() -> Array[int]:
	return [
		TraitId.STAT_AD,
		TraitId.STAT_AP,
		TraitId.STAT_HP,
		TraitId.STAT_ATK_SPD,
		TraitId.STAT_HASTE,
		TraitId.STAT_MOVE_SPD
	]
