@icon( "res://general/icons/state.svg" )
class_name PlayerStateJump extends PlayerState

@onready var sprite_2d: Sprite2D = $"../../Sprite2D"
@onready var sprite_2d_2: Sprite2D = $"../../Sprite2D2"

const JUMP = preload("uid://cwhvso8ircol")
@export var jump_velocity : float = 450
#状态初始化时做什么
func init() -> void:
	pass
	
#当我们进入这个状态时会发生什么
func enter() -> void:
	#动画
	sprite_2d.visible = true
	sprite_2d_2.visible = false
	if player.is_on_floor():
		VisualEffects.jump_dust( player.global_position )
	else:
		VisualEffects.hit_dust( player.global_position )
	player.animation_player.play( "jump" )
	player.animation_player.pause()
	#player.add_debug_indicator( Color.LAWN_GREEN )
	do_jump()
	if player.previous_state == fall and not Input.is_action_pressed("jump"):
		await get_tree().physics_frame
		player.velocity.y *= 0.5
		player.change_state( fall )
		pass
		
	pass
	
#当我们退出这个状态会发生什么
func exit() -> void:
	sprite_2d.visible = false
	sprite_2d_2.visible = true
	#player.add_debug_indicator( Color.YELLOW )
	pass

#按下输入会发生什么
func handle_input( event : InputEvent ) -> PlayerState:
	#处理输入
	if event.is_action_pressed( "dash" ) and player.can_dash():
		return dash
	if event.is_action_pressed("attack"):
		if player.ground_slam and Input.is_action_pressed( "down" ):
			return ground_slam
		return attack
	if event.is_action_released("jump"):
		return fall
	return next_state
	
	
#在这个状态下，每个过程tick会发生什么
func process(_delta: float) -> PlayerState:
	set_jump_frame()
	return next_state


#在这个状态下，每个物理过程tick会发生什么
func physics_process(_delta: float) -> PlayerState:
	if player.is_on_floor():
		return idle
	elif player.velocity.y >= 0:
		return fall
	player.velocity.x = player.direction.x * player.move_speed
	return next_state


func do_jump() -> void:
	if player.jump_count > 0:
		if player.double_jump == false:
			return
		elif player.jump_count > 1:
			return
	player.jump_count += 1
	player.velocity.y = -jump_velocity
	Audio.play_spatial_sound( JUMP , player.global_position , false , true , 0.25 )
	pass


func set_jump_frame() -> void:
	var frame : float = remap( player.velocity.y,-jump_velocity,0.0,0.0,0.5 )
	player.animation_player.seek( frame,true )
	pass
