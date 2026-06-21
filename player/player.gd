extends CharacterBody2D

const SPEED = 200.0
var move_direction := Vector2.ZERO

func _process(delta: float) -> void:
	move_direction = Vector2.ZERO
	if Input.is_action_pressed("move_right"):
		move_direction.x += 1
	if Input.is_action_pressed("move_left"):
		move_direction.x -= 1
	if Input.is_action_pressed("move_down"):
		move_direction.y += 1
	if Input.is_action_pressed("move_up"):
		move_direction.y -= 1
	
	if move_direction != Vector2.ZERO:
		move_direction = move_direction.normalized()

func _physics_process(delta: float) -> void:
	velocity = move_direction * SPEED
	move_and_slide()
