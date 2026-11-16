class_name GrassTileStamper
extends RefCounted

## Tiles and polygon-crops the pre-baked 25m x 25m grass_multimesh.tres across
## arbitrary room and bridge polygons while preserving 100% of original QuadMesh
## geometry, +Y lighting normals (basis.z = (0, 1.001, 0)), and 48 blades/m^2 density.

const TILE_SIZE: float = 25.0
const HALF_TILE: float = 12.5
const GRID_DIVS: int = 5
const CELL_SIZE: float = TILE_SIZE / float(GRID_DIVS) # 5.0m per spatial bucket
const FLOATS_PER_INSTANCE: int = 12

var _source_mesh: Mesh = null
# Array of 25 PackedFloat32Arrays (one per 5m x 5m bucket in the 25m x 25m master tile)
var _cell_buffers: Array[PackedFloat32Array] = []
var _is_initialized: bool = false


func initialize(source_mm: MultiMesh) -> void:
	if _is_initialized or source_mm == null:
		return

	_source_mesh = source_mm.mesh
	_cell_buffers.clear()
	for _idx in range(GRID_DIVS * GRID_DIVS):
		_cell_buffers.append(PackedFloat32Array())

	var raw_buf: PackedFloat32Array = source_mm.buffer
	var total_instances: int = source_mm.instance_count
	var active_count: int = source_mm.visible_instance_count if source_mm.visible_instance_count > 0 else total_instances
	active_count = mini(active_count, total_instances)
	active_count = mini(active_count, floori(float(raw_buf.size()) / float(FLOATS_PER_INSTANCE)))

	for i in range(active_count):
		var base: int = i * FLOATS_PER_INSTANCE
		var ox: float = raw_buf[base + 3]
		var oz: float = raw_buf[base + 11]

		var cx: int = clampi(int(floor((ox + HALF_TILE) / CELL_SIZE)), 0, GRID_DIVS - 1)
		var cz: int = clampi(int(floor((oz + HALF_TILE) / CELL_SIZE)), 0, GRID_DIVS - 1)
		var bucket_idx: int = cz * GRID_DIVS + cx

		var cell_buf: PackedFloat32Array = _cell_buffers[bucket_idx]
		for f in range(FLOATS_PER_INSTANCE):
			cell_buf.append(raw_buf[base + f])

	_is_initialized = true


## Stamps and crops grass transforms inside `world_poly` (2D XZ coordinates),
## returning a MultiMesh whose origins are relative to `section_center` (for tight local AABB culling).
## Optional `inner_safe_rect` (in world XZ) fast-accepts interior 5m x 5m cells without polygon tests.
func stamp_polygon(
	world_poly: PackedVector2Array,
	section_center: Vector2,
	inner_safe_rect: Rect2 = Rect2()
) -> MultiMesh:
	if not _is_initialized or world_poly.size() < 3:
		return null

	# Compute world-space AABB of the target polygon
	var min_x: float = INF
	var min_z: float = INF
	var max_x: float = -INF
	var max_z: float = -INF
	for pt in world_poly:
		min_x = minf(min_x, pt.x)
		min_z = minf(min_z, pt.y)
		max_x = maxf(max_x, pt.x)
		max_z = maxf(max_z, pt.y)

	var poly_aabb := Rect2(min_x, min_z, max_x - min_x, max_z - min_z)
	var has_safe_rect: bool = inner_safe_rect.size.x > 0.1 and inner_safe_rect.size.y > 0.1

	# Global 25m x 25m tile indices covering [min_x..max_x, min_z..max_z]
	# Tile (tx, tz) is centered at (tx * 25.0, tz * 25.0) and spans [-12.5..+12.5] around its center
	var min_tx: int = int(floor((min_x + HALF_TILE) / TILE_SIZE))
	var max_tx: int = int(floor((max_x + HALF_TILE) / TILE_SIZE))
	var min_tz: int = int(floor((min_z + HALF_TILE) / TILE_SIZE))
	var max_tz: int = int(floor((max_z + HALF_TILE) / TILE_SIZE))

	var out_buf := PackedFloat32Array()

	for tz in range(min_tz, max_tz + 1):
		var tile_world_z: float = float(tz) * TILE_SIZE
		for tx in range(min_tx, max_tx + 1):
			var tile_world_x: float = float(tx) * TILE_SIZE

			# Shift from master tile space -> local section space directly:
			# world_pos = tile_world + blade_master_pos
			# local_pos = world_pos - section_center
			var local_shift_x: float = tile_world_x - section_center.x
			var local_shift_z: float = tile_world_z - section_center.y

			for cz in range(GRID_DIVS):
				var cell_min_z: float = tile_world_z - HALF_TILE + float(cz) * CELL_SIZE
				for cx in range(GRID_DIVS):
					var cell_min_x: float = tile_world_x - HALF_TILE + float(cx) * CELL_SIZE
					var cell_rect := Rect2(cell_min_x, cell_min_z, CELL_SIZE, CELL_SIZE)

					if not poly_aabb.intersects(cell_rect):
						continue

					var cell_buf: PackedFloat32Array = _cell_buffers[cz * GRID_DIVS + cx]
					var cell_float_len: int = cell_buf.size()
					if cell_float_len == 0:
						continue

					# Fast-accept entire 5m x 5m cell if enclosed within inner safe box
					if has_safe_rect and inner_safe_rect.encloses(cell_rect):
						var write_idx: int = out_buf.size()
						out_buf.resize(write_idx + cell_float_len)
						var idx: int = 0
						while idx < cell_float_len:
							out_buf[write_idx + idx] = cell_buf[idx]
							out_buf[write_idx + idx + 1] = cell_buf[idx + 1]
							out_buf[write_idx + idx + 2] = cell_buf[idx + 2]
							out_buf[write_idx + idx + 3] = cell_buf[idx + 3] + local_shift_x
							out_buf[write_idx + idx + 4] = cell_buf[idx + 4]
							out_buf[write_idx + idx + 5] = cell_buf[idx + 5]
							out_buf[write_idx + idx + 6] = cell_buf[idx + 6]
							out_buf[write_idx + idx + 7] = cell_buf[idx + 7]
							out_buf[write_idx + idx + 8] = cell_buf[idx + 8]
							out_buf[write_idx + idx + 9] = cell_buf[idx + 9]
							out_buf[write_idx + idx + 10] = cell_buf[idx + 10]
							out_buf[write_idx + idx + 11] = cell_buf[idx + 11] + local_shift_z
							idx += FLOATS_PER_INSTANCE
					else:
						# Boundary cell: exact point-in-polygon crop
						var idx: int = 0
						while idx < cell_float_len:
							var wx: float = tile_world_x + cell_buf[idx + 3]
							var wz: float = tile_world_z + cell_buf[idx + 11]
							if wx >= min_x and wx <= max_x and wz >= min_z and wz <= max_z:
								if Geometry2D.is_point_in_polygon(Vector2(wx, wz), world_poly):
									var write_idx: int = out_buf.size()
									out_buf.resize(write_idx + FLOATS_PER_INSTANCE)
									out_buf[write_idx] = cell_buf[idx]
									out_buf[write_idx + 1] = cell_buf[idx + 1]
									out_buf[write_idx + 2] = cell_buf[idx + 2]
									out_buf[write_idx + 3] = wx - section_center.x
									out_buf[write_idx + 4] = cell_buf[idx + 4]
									out_buf[write_idx + 5] = cell_buf[idx + 5]
									out_buf[write_idx + 6] = cell_buf[idx + 6]
									out_buf[write_idx + 7] = cell_buf[idx + 7]
									out_buf[write_idx + 8] = cell_buf[idx + 8]
									out_buf[write_idx + 9] = cell_buf[idx + 9]
									out_buf[write_idx + 10] = cell_buf[idx + 10]
									out_buf[write_idx + 11] = wz - section_center.y
							idx += FLOATS_PER_INSTANCE

	var kept_instances: int = floori(float(out_buf.size()) / float(FLOATS_PER_INSTANCE))
	if kept_instances <= 0:
		return null

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _source_mesh
	mm.instance_count = kept_instances
	mm.visible_instance_count = kept_instances
	mm.buffer = out_buf
	return mm
