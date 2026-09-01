class_name PlayerStateDeath extends PlayerState

const DEATH_01 = preload("uid://dwh80hhj3giq7")


@onready var sprite_2d: Sprite2D = $"../../Sprite2D"
@onready var sprite_2d_2: Sprite2D = $"../../Sprite2D2"



#状态初始化时做什么
func init() -> void:
	pass
	
	
#当我们进入这个状态时会发生什么
func enter() -> void:
	#动画
	sprite_2d.visible = true
	sprite_2d_2.visible = false
	player.animation_player.play( "death" )
	Audio.play_spatial_sound( DEATH_01 , player.global_position )
	Audio.play_music( null )
	take_damage.damage_area.visible = false
	await player.animation_player.animation_finished
	PlayerHud.show_game_over()
	pass
	
#当我们退出这个状态会发生什么
func exit() -> void:
	pass

#按下输入会发生什么
func handle_input( _event : InputEvent ) -> PlayerState:
	#处理输入

	return null
	
	
#在这个状态下，每个过程tick会发生什么
func process(_delta: float) -> PlayerState:

	return null


#在这个状态下，每个物理过程tick会发生什么
func physics_process(_delta: float) -> PlayerState:
	player.velocity.x = 0
	return null
