extends Node2D

const NUM_TREES = 100
const MAP_SIZE = 2000

func _ready() -> void:
	# Add ground ColorRect
	var ground = ColorRect.new()
	ground.size = Vector2(MAP_SIZE * 2, MAP_SIZE * 2)
	ground.position = Vector2(-MAP_SIZE, -MAP_SIZE)
	ground.color = Color("#14532d") # Grassy green
	ground.show_behind_parent = true
	ground.z_index = -10
	add_child(ground)
	
	# Spawn trees
	for i in range(NUM_TREES):
		var tree = StaticBody2D.new()
		
		# Set random position (avoid spawning exactly at player's start position)
		var rx := 0.0
		var ry := 0.0
		while true:
			rx = randf_range(-MAP_SIZE + 100, MAP_SIZE - 100)
			ry = randf_range(-MAP_SIZE + 100, MAP_SIZE - 100)
			if Vector2(rx, ry).distance_to(Vector2(576, 324)) > 150:
				break
				
		tree.position = Vector2(rx, ry)
		
		# Trunk (ColorRect)
		var trunk = ColorRect.new()
		trunk.name = "Trunk"
		trunk.size = Vector2(12, 30)
		trunk.position = Vector2(-6, -30)
		trunk.color = Color("#78350f") # Brown
		tree.add_child(trunk)
		
		# Foliage layer 1 (Polygon2D)
		var foliage = Polygon2D.new()
		foliage.name = "Foliage"
		foliage.color = Color("#15803d") # Green
		var points = PackedVector2Array([
			Vector2(0, -75),
			Vector2(-30, -25),
			Vector2(30, -25)
		])
		foliage.polygon = points
		tree.add_child(foliage)
		
		# Foliage layer 2 (Polygon2D)
		var foliage2 = Polygon2D.new()
		foliage2.name = "Foliage2"
		foliage2.color = Color("#166534") # Darker green top
		var points2 = PackedVector2Array([
			Vector2(0, -95),
			Vector2(-20, -50),
			Vector2(20, -50)
		])
		foliage2.polygon = points2
		tree.add_child(foliage2)

		# Collision
		var collision = CollisionShape2D.new()
		collision.name = "CollisionShape2D"
		var shape = CircleShape2D.new()
		shape.radius = 8
		collision.shape = shape
		collision.position = Vector2(0, -5)
		tree.add_child(collision)
		
		# Add tree to Main
		add_child(tree)
