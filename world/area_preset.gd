class_name AreaPreset
extends RefCounted

## Presets and geometry generators for Cult of the Lamb-style rectangular sections
## and cardinal bridges (Left, Right, Up, Down).

enum RoomRole {
	SPAWN,   ## Starting room
	COMBAT,  ## Standard combat arena
	LARGE,   ## Event / elite arena
	DEADEND, ## 1-path deep side chamber (treasure, shrine, challenge)
	BOSS     ## Final boss arena
}

## Returns rectangular dimensions for a given room role
static func get_room_size(role: RoomRole, rng: RandomNumberGenerator) -> Vector2:
	match role:
		RoomRole.SPAWN:
			return Vector2(rng.randf_range(20.0, 24.0), rng.randf_range(16.0, 20.0))
		RoomRole.COMBAT:
			return Vector2(rng.randf_range(25.0, 30.0), rng.randf_range(19.0, 24.0))
		RoomRole.LARGE:
			return Vector2(rng.randf_range(30.0, 36.0), rng.randf_range(22.0, 28.0))
		RoomRole.DEADEND:
			return Vector2(rng.randf_range(18.0, 22.0), rng.randf_range(16.0, 20.0))
		RoomRole.BOSS:
			return Vector2(rng.randf_range(34.0, 40.0), rng.randf_range(26.0, 32.0))
	return Vector2(26.0, 20.0)

## Builds a clean, large rectangular polygon with rounded corners
static func build_rounded_rectangle(
	center: Vector2,
	size: Vector2,
	corner_radius: float = 3.0,
	corner_segments: int = 8
) -> PackedVector2Array:
	var half_w: float = size.x * 0.5
	var half_h: float = size.y * 0.5
	var r: float = minf(corner_radius, minf(half_w, half_h) * 0.4)

	var poly := PackedVector2Array()

	# 4 Corner arc centers: Top-Right, Bottom-Right, Bottom-Left, Top-Left
	var centers := [
		center + Vector2(half_w - r, -half_h + r), # Top-Right
		center + Vector2(half_w - r, half_h - r),  # Bottom-Right
		center + Vector2(-half_w + r, half_h - r), # Bottom-Left
		center + Vector2(-half_w + r, -half_h + r) # Top-Left
	]

	var start_angles := [
		-PI * 0.5, # Top-Right: -90 deg to 0 deg
		0.0,       # Bottom-Right: 0 deg to 90 deg
		PI * 0.5,  # Bottom-Left: 90 deg to 180 deg
		PI         # Top-Left: 180 deg to 270 deg
	]

	for c_idx in range(4):
		var arc_c: Vector2 = centers[c_idx]
		var base_a: float = start_angles[c_idx]
		for i in range(corner_segments + 1):
			var a: float = base_a + (PI * 0.5) * (float(i) / float(corner_segments))
			poly.append(arc_c + Vector2(cos(a), sin(a)) * r)

	return poly

## Builds a clean cardinal bridge ribbon connecting two rooms along X or Y axis
static func build_cardinal_bridge(
	pos1: Vector2,
	size1: Vector2,
	pos2: Vector2,
	size2: Vector2,
	bridge_width: float
) -> PackedVector2Array:
	var diff := pos2 - pos1
	var half_w := bridge_width * 0.5
	var poly := PackedVector2Array()

	# Overlap depth inside rooms so boolean union merges flawlessly
	var overlap: float = 1.0

	if absf(diff.x) > absf(diff.y):
		# Horizontal bridge (Left <-> Right)
		var left_x: float = 0.0
		var right_x: float = 0.0
		var y_center: float = (pos1.y + pos2.y) * 0.5

		if diff.x > 0:
			# pos1 is left, pos2 is right
			left_x = pos1.x + size1.x * 0.5 - overlap
			right_x = pos2.x - size2.x * 0.5 + overlap
		else:
			# pos2 is left, pos1 is right
			left_x = pos2.x + size2.x * 0.5 - overlap
			right_x = pos1.x - size1.x * 0.5 + overlap

		poly.append(Vector2(left_x, y_center - half_w))
		poly.append(Vector2(right_x, y_center - half_w))
		poly.append(Vector2(right_x, y_center + half_w))
		poly.append(Vector2(left_x, y_center + half_w))
	else:
		# Vertical bridge (Up <-> Down)
		var top_y: float = 0.0
		var bottom_y: float = 0.0
		var x_center: float = (pos1.x + pos2.x) * 0.5

		if diff.y > 0:
			# pos1 is top, pos2 is bottom
			top_y = pos1.y + size1.y * 0.5 - overlap
			bottom_y = pos2.y - size2.y * 0.5 + overlap
		else:
			# pos2 is top, pos1 is bottom
			top_y = pos2.y + size2.y * 0.5 - overlap
			bottom_y = pos1.y - size1.y * 0.5 + overlap

		poly.append(Vector2(x_center - half_w, top_y))
		poly.append(Vector2(x_center + half_w, top_y))
		poly.append(Vector2(x_center + half_w, bottom_y))
		poly.append(Vector2(x_center - half_w, bottom_y))

	return poly
