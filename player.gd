extends CharacterBody2D

const SPEED = 250.0

func _physics_process(_delta):
	var direction = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	velocity = direction * SPEED
	move_and_slide()

	if Input.is_action_just_pressed("ui_accept"):
		kill_nearest_enemy()

func kill_nearest_enemy():
	var enemies = get_tree().get_nodes_in_group("enemies")
	var nearest_enemy = null
	var min_dist = INF
	
	for enemy in enemies:
		if enemy.is_alive:
			var dist = global_position.distance_to(enemy.global_position)
			if dist < min_dist:
				min_dist = dist
				nearest_enemy = enemy
				
	if nearest_enemy != null:
		nearest_enemy.die()

func _ready():
	add_to_group("player")
