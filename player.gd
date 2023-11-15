extends CharacterBody2D

@export var speed = 400.0
@export var jump_velocity  = -650.0
@export var jump_count = 2
@export var gravity_multiplier = 2.0
@export var currentLevel:Node2D

var current_jumps = 0

# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")


func _physics_process(delta):
	apply_gravity(delta)
	handle_jump()
	handle_movement()


func apply_gravity(delta):
	if not is_on_floor():
		velocity.y += gravity * gravity_multiplier * delta

func handle_jump():
	if is_on_floor(): 
		current_jumps = 0
	
	if Input.is_action_just_pressed("ui_accept"):
		if is_on_floor() or current_jumps < jump_count:
			velocity.y = jump_velocity
			current_jumps += 1

func handle_movement():
	var direction = Input.get_axis("ui_left", "ui_right")
	if direction:
		velocity.x = direction * speed
		$GFX.flip_h = direction < 0 
	else:
		velocity.x = move_toward(velocity.x, 0, speed)

	move_and_slide()
	
	


func _on_area_2d_body_entered(body):
	if body.is_in_group("collectible"):
		currentLevel.update_ui_score(body.value)
		body.Collect()
		
