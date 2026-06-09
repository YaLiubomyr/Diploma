extends CharacterBody2D

# Carries the enemy's traits to the level generator when it dies
signal died(genome)

var speed: float = 150.0
var vision_radius: float = 200.0 
var home_room: Rect2i

# Accumulates time spent actively chasing the player; used as fitness score
var time_in_combat: float = 0.0 
var is_alive: bool = true
var is_active: bool = false 

var attack_distance: float = 40.0

var player: Node2D
var tilemap: TileMapLayer
@onready var nav_agent = $NavigationAgent2D
@onready var raycast = $RayCast2D 

func _ready():
	add_to_group("enemies")

func _physics_process(delta):
	if not is_alive or player == null: return
	
	# Point the raycast at the player and force an immediate update for line-of-sight check
	raycast.target_position = to_local(player.global_position)
	raycast.force_raycast_update()
	var dist_to_player = global_position.distance_to(player.global_position)
	
	# Convert world position to tile coordinates to check if the player is in this enemy's room
	var player_in_room = false
	if tilemap != null and home_room != Rect2i():
		var player_tile = tilemap.local_to_map(tilemap.to_local(player.global_position))
		player_in_room = home_room.has_point(player_tile)
	
	# Activate only when the player is in the same room, within range, and not behind a wall
	if player_in_room and not raycast.is_colliding() and dist_to_player <= vision_radius:
		is_active = true
	elif not player_in_room or dist_to_player > vision_radius:
		is_active = false
	
	if is_active:
		time_in_combat += delta
		
		# Chase the player via navigation; stop and hold position when close enough
		if dist_to_player > attack_distance:
			nav_agent.target_position = player.global_position
			var next_path_pos = nav_agent.get_next_path_position()
			velocity = global_position.direction_to(next_path_pos) * speed
		else:
			velocity = Vector2.ZERO
		move_and_slide()

func die():
	is_alive = false
	modulate.a = 0.3 
	$CollisionShape2D.set_deferred("disabled", true)
	
	print("The enemy is dead. Speed: ", snapped(speed, 0.1), ", Vision: ", snapped(vision_radius, 0.1), ", Time in battle: ", snapped(time_in_combat, 0.1))
	
	# Pack traits into a genome dict; time_survived is the fitness value for selection
	var genome = {
		"speed": speed,
		"vision_radius": vision_radius,
		"time_survived": time_in_combat 
	}
	died.emit(genome)
