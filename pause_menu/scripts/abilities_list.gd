extends Node


@onready var ability_double_jump: TextureRect = %AbilityDoubleJump
@onready var ability_dash: TextureRect = %AbilityDash
@onready var ability_ground_slam: TextureRect = %AbilityGroundSlam
@onready var ability_ground_climb: TextureRect = %AbilityGroundClimb



func _ready() -> void:
	var player : Player = get_tree().get_first_node_in_group( "Player" )
	#标题界面等无玩家场景：全部能力图标隐藏，避免访问空实例
	if player == null:
		ability_dash.visible = false
		ability_double_jump.visible = false
		ability_ground_slam.visible = false
		ability_ground_climb.visible = false
		return
	ability_dash.visible = player.dash
	ability_double_jump.visible = player.double_jump
	ability_ground_slam.visible = player.ground_slam
	ability_ground_climb.visible = player.wall_climb
	pass
