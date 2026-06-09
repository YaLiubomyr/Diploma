extends Node2D

@export_group("Map Generation Settings")
@export_range(20, 200) var map_width: int = 60
@export_range(20, 200) var map_height: int = 40
@export_range(10, 50) var min_leaf_size: int = 15

@export_group("Scenes to Spawn")
@export var player_scene: PackedScene
@export var enemy_scene: PackedScene
@export var obstacle_scene: PackedScene

@export_group("Enemy Spawn Settings")
@export_range(1, 50) var min_enemies_per_room: int = 1
@export_range(1, 50) var max_enemies_per_room: int = 3
@export_range(0, 5) var min_obstacles_per_room: int = 1
@export_range(1, 10) var max_obstacles_per_room: int = 3

@export_group("Evolution & Mutation Settings")
@export var evolve_speed: bool = true
@export var evolve_vision: bool = true
@export_range(0.0, 1.0) var mutation_factor: float = 0.15
@export_range(0.1, 0.9) var survival_rate: float = 0.5
@export_range(10.0, 100.0) var min_enemy_speed: float = 50.0
@export_range(100.0, 500.0) var max_enemy_speed: float = 240.0
@export_range(1.0, 300.0) var min_enemy_vision: float = 100.0
@export_range(1.0, 1000.0) var max_enemy_vision: float = 800.0

@export_group("System Settings")
@export var show_hud: bool = true
@export_range(1, 100) var max_levels: int = 5
@export var map_seed: int = 0

@export_group("Tile Settings")
@export var floor_tile_coords: Vector2i = Vector2i(3, 2)
@export var wall_tile_coords: Vector2i = Vector2i(0, 0)

@onready var tile_map = $TileMapLayer
@onready var hud_label = $HUD/Label

var root_leaf: Leaf
var leaves: Array[Leaf] = []
var current_generation_genomes: Array = []
var dead_enemies_data: Array = []
var enemies_alive: int = 0
var generation_number: int = 1

class Leaf:
	var x: int
	var y: int
	var width: int
	var height: int
	var left_child: Leaf
	var right_child: Leaf
	
	var room: Rect2i
	var hall_points: Array[Vector2i] = []

	func _init(_x: int, _y: int, _w: int, _h: int):
		x = _x
		y = _y
		width = _w
		height = _h

	func split(min_size: int) -> bool:
		if left_child != null or right_child != null:
			return false
		var split_horizontally: bool = randf() > 0.5
		
		# Bias the split direction toward the longer axis to keep partitions roughly square
		if width > height and width / float(height) >= 1.25:
			split_horizontally = false
		elif height > width and height / float(width) >= 1.25:
			split_horizontally = true
		
		# Ensure both halves are at least min_size; abort if there is not enough room	
		var max_split: int = (height if split_horizontally else width) - min_size
		if max_split <= min_size:
			return false
			
		var split_val: int = randi_range(min_size, max_split)
		if split_horizontally:
			left_child = Leaf.new(x, y, width, split_val)
			right_child = Leaf.new(x, y + split_val, width, height - split_val)
		else:
			left_child = Leaf.new(x, y, split_val, height)
			right_child = Leaf.new(x + split_val, y, width - split_val, height)
		return true

	func create_rooms(min_size: int):
		if left_child != null or right_child != null:
			if left_child != null: left_child.create_rooms(min_size)
			if right_child != null: right_child.create_rooms(min_size)
			
			if left_child != null and right_child != null:
				var left_rooms = left_child.get_all_leaf_rooms()
				var right_rooms = right_child.get_all_leaf_rooms()
				
				var best_a: Rect2i
				var best_b: Rect2i
				var min_dist = INF
				
				# Find the closest room pair across the two subtrees and connect them with a corridor
				for a in left_rooms:
					for b in right_rooms:
						var dist = a.get_center().distance_squared_to(b.get_center())
						if dist < min_dist:
							min_dist = dist
							best_a = a
							best_b = b
							
				if best_a != Rect2i() and best_b != Rect2i():
					create_hall(best_a, best_b)
		else:
			var room_w = randi_range(min_size / 2, width - 4)
			var room_h = randi_range(min_size / 2, height - 4)
			var room_pos_x = randi_range(2, width - room_w - 2)
			var room_pos_y = randi_range(2, height - room_h - 2)
			room = Rect2i(x + room_pos_x, y + room_pos_y, room_w, room_h)

	func get_all_leaf_rooms() -> Array[Rect2i]:
		var arr: Array[Rect2i] = []
		if room != Rect2i():
			arr.append(room)
		if left_child != null:
			arr.append_array(left_child.get_all_leaf_rooms())
		if right_child != null:
			arr.append_array(right_child.get_all_leaf_rooms())
		return arr

	# Builds an L-shaped corridor: moves horizontally first when going right, vertically first otherwise
	func create_hall(room_a: Rect2i, room_b: Rect2i):
		hall_points.clear()
		var current = room_a.get_center()
		var target = room_b.get_center()

		if current.x < target.x:
			while current.x != target.x:
				hall_points.append(current)
				current.x += sign(target.x - current.x)
			while current.y != target.y:
				hall_points.append(current)
				current.y += sign(target.y - current.y)
		else:
			while current.y != target.y:
				hall_points.append(current)
				current.y += sign(target.y - current.y)
			while current.x != target.x:
				hall_points.append(current)
				current.x += sign(target.x - current.x)
				
		hall_points.append(target)

func _ready():
	if map_seed != 0:
		seed(map_seed)
	else:
		randomize()
		map_seed = randi()
		seed(map_seed)
	
	print("--- CURRENT WORLD SEED: ", map_seed, " ---")
		
	generate_bsp()
	draw_tiles()
	spawn_obstacles()
	start_new_generation()

func generate_bsp():
	root_leaf = Leaf.new(0, 0, map_width, map_height)
	leaves.append(root_leaf)
	var did_split: bool = true
	
	# Keep splitting leaves until no leaf is large enough to be divided further
	while did_split:
		did_split = false
		for i in range(leaves.size()):
			var leaf = leaves[i]
			if leaf.left_child == null and leaf.right_child == null:
				if leaf.width > min_leaf_size or leaf.height > min_leaf_size:
					if leaf.split(min_leaf_size):
						leaves.append(leaf.left_child)
						leaves.append(leaf.right_child)
						did_split = true
	
	root_leaf.create_rooms(min_leaf_size)

# Fill the entire map with walls first, then carve corridors and rooms on top
func draw_tiles():
	if tile_map == null: return
	tile_map.clear()
	
	for x in range(map_width):
		for y in range(map_height):
			tile_map.set_cell(Vector2i(x, y), 0, wall_tile_coords)
			
	draw_all_halls(root_leaf)
	
	draw_all_rooms(root_leaf)

func draw_all_halls(leaf: Leaf):
	if leaf == null: return
	for point in leaf.hall_points:
		tile_map.set_cell(point, 0, floor_tile_coords)
	if leaf.left_child != null: draw_all_halls(leaf.left_child)
	if leaf.right_child != null: draw_all_halls(leaf.right_child)

func draw_all_rooms(leaf: Leaf):
	if leaf == null: return
	if leaf.room != Rect2i():
		for x in range(leaf.room.position.x, leaf.room.end.x):
			for y in range(leaf.room.position.y, leaf.room.end.y):
				tile_map.set_cell(Vector2i(x, y), 0, floor_tile_coords) 
	if leaf.left_child != null: draw_all_rooms(leaf.left_child)
	if leaf.right_child != null: draw_all_rooms(leaf.right_child)

func spawn_obstacles():
	var rooms = get_all_rooms(root_leaf)
	
	for room in rooms:
		var num_obstacles = randi_range(min_obstacles_per_room, max_obstacles_per_room)
		
		for j in range(num_obstacles):
			if obstacle_scene != null:
				var obs = obstacle_scene.instantiate()
				obs.position = get_random_pos_in_room(room)
				
				obs.rotation = randf_range(0, PI * 2) 
				obs.add_to_group("obstacles")
				
				add_child(obs)

func start_new_generation():
	print("--- GENERATION ", generation_number, " ---")
	dead_enemies_data.clear()
	enemies_alive = 0
	
	var rooms = get_all_rooms(root_leaf)
	if rooms.size() == 0: return

	var player_instance = null
	var players_in_scene = get_tree().get_nodes_in_group("player")
	
	if players_in_scene.size() == 0:
		if player_scene != null:
			player_instance = player_scene.instantiate()
			player_instance.position = tile_map.map_to_local(rooms[0].get_center())
			add_child(player_instance)
	else:
		player_instance = players_in_scene[0]
		player_instance.position = tile_map.map_to_local(rooms[0].get_center())

	for i in range(1, rooms.size()):
		var num_enemies = randi_range(min_enemies_per_room, max_enemies_per_room)
		for j in range(num_enemies):
			if enemy_scene != null:
				var enemy = enemy_scene.instantiate()
				enemy.position = get_random_pos_in_room(rooms[i])
				enemy.player = player_instance
				enemy.home_room = rooms[i]
				enemy.tilemap = tile_map 
				
				# If a previous generation exists, seed the new enemy's traits from a random survivor
				if current_generation_genomes.size() > 0:
					var random_genome = current_generation_genomes.pick_random()
					enemy.speed = random_genome["speed"]
					if random_genome.has("vision_radius"):
						enemy.vision_radius = random_genome["vision_radius"]
				
				enemy.died.connect(_on_enemy_died)
				add_child(enemy)
				enemies_alive += 1
				
	update_hud()

func _on_enemy_died(genome):
	dead_enemies_data.append(genome)
	enemies_alive -= 1
	
	update_hud()
	
	if enemies_alive <= 0:
		print("All the enemies of generation ", generation_number, " have been destroyed!")
		evolve_population()

func evolve_population():
	# Sort by survival time descending: enemies that lasted longer are considered more fit
	dead_enemies_data.sort_custom(func(a, b): return a["time_survived"] > b["time_survived"])
	
	var new_genomes: Array = []
	var population_size = dead_enemies_data.size()
	
	# Only the top fraction of the population is eligible to be selected as parents
	var elite_count = max(1, int(population_size * survival_rate))
	
	for i in range(population_size):
		var parent_a = dead_enemies_data[randi() % elite_count]
		var parent_b = dead_enemies_data[randi() % elite_count]
		
		# Crossover: randomly inherit speed and vision from different parents
		var child_speed = parent_a["speed"]
		var child_vision = parent_b["vision_radius"]
		
		if randf() > 0.5:
			child_speed = parent_b["speed"]
			child_vision = parent_a["vision_radius"]
		
		# Apply multiplicative mutation; result is clamped to stay within configured limits
		if evolve_speed:
			child_speed *= randf_range(1.0 - mutation_factor, 1.0 + mutation_factor)
			child_speed = clamp(child_speed, min_enemy_speed, max_enemy_speed)
			
		if evolve_vision:
			child_vision *= randf_range(1.0 - mutation_factor, 1.0 + mutation_factor)
			child_vision = clamp(child_vision, min_enemy_vision, max_enemy_vision)
			
		new_genomes.append({
			"speed": child_speed,
			"vision_radius": child_vision
		})
		
	current_generation_genomes = new_genomes
	generation_number += 1
	
	if generation_number > max_levels:
		print("YOU WIN! All levels cleared.")
		if hud_label != null and show_hud:
			hud_label.text = "YOU WIN! All " + str(max_levels) + " levels cleared."
		return 
		
	print("Preparing a new level for generation ", generation_number)
	
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	for o in get_tree().get_nodes_in_group("obstacles"):
		o.queue_free()
		
	await get_tree().create_timer(1.5).timeout
	
	leaves.clear() 
	generate_bsp()
	draw_tiles()
	spawn_obstacles()
	start_new_generation()

func get_all_rooms(leaf: Leaf) -> Array[Rect2i]:
	var rooms: Array[Rect2i] = []
	if leaf == null: 
		return rooms
		
	if leaf.room != Rect2i():
		rooms.append(leaf.room)
		
	rooms.append_array(get_all_rooms(leaf.left_child))
	rooms.append_array(get_all_rooms(leaf.right_child))
	return rooms

func get_random_pos_in_room(room: Rect2i) -> Vector2:	
	var rand_tx = randi_range(room.position.x + 1, room.end.x - 2)
	var rand_ty = randi_range(room.position.y + 1, room.end.y - 2)
		
	return tile_map.map_to_local(Vector2i(rand_tx, rand_ty))

func update_hud():
	if hud_label != null:
		if show_hud:
			hud_label.show()
			hud_label.text = "Generation: " + str(generation_number) + " / " + str(max_levels) + "\nEnemies left: " + str(enemies_alive)
		else:
			hud_label.hide()
