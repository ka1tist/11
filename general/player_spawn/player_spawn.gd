@icon("res://general/icons/player_spawn.svg")
class_name PlayerSpawn extends Node2D



func _ready() -> void:
	visible = false
	await get_tree().process_frame
	
	var player : Player = load("res://player/player.tscn").instantiate()
	get_tree().root.add_child ( player )
	player.global_position = self.global_position
	pass
