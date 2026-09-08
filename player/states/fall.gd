@icon( "res://general/icons/state.svg" )
class_name PlayerStateFall extends PlayerState

@onready var sprite_2d: Sprite2D = $"../../Sprite2D"
@onready var sprite_2d_2: Sprite2D = $"../../Sprite2D2"

const LAND = preload("uid://bkjtuekmdg035")


@export var fal_gravity_mulitplier : float = 1.165
@export var coyote_time : float = 0.125
@export var jump_buffer_time : float = 0.2
@export var long_fall_time : float = 1.0
@export var land_lock_time : float = 0.36
@export var long_fall_land_volume : float = 16.0

var coyote_timer : float = 0
var buffer_timer : float = 0
var fall_timer : float = 0
var land_lock_timer : float = 0

#状态初始化时做什么
func init() -> void:
	pass
	
#当我们进入这个状态时会发生什么
func enter() -> void:
	#动画
	sprite_2d.visible = true
	sprite_2d_2.visible = false
	player.animation_player.play( "jump" )
	player.animation_player.pause()
	player.gravity_mulitplier = fal_gravity_mulitplier

	fall_timer = 0
	land_lock_timer = 0
	if player.jump_count == 0:
		player.jump_count = 1
	
	var prev : PlayerState = player.previous_state
	if prev == jump or prev == run or prev == dash:
		coyote_timer = 0
	elif player.previous_state == crouch:
		coyote_timer = 0
		player.jump_count = 1
	else:
		coyote_timer = coyote_time
	pass
	
#当我们退出这个状态会发生什么
func exit() -> void:
	sprite_2d.visible = false
	sprite_2d_2.visible = true
	player.gravity_mulitplier = 1.0
	buffer_timer = 0
	land_lock_timer = 0
	pass

#按下输入会发生什么
func handle_input( _event : InputEvent ) -> PlayerState:
	#长下落落地恢复期间不能操作
	if land_lock_timer > 0:
		return next_state
	#处理输入
	if _event.is_action_pressed( "dash" ) and player.can_dash():
		return dash
	if _event.is_action_pressed("attack"):
		if player.ground_slam and Input.is_action_pressed( "down" ):
			return ground_slam
		return attack
	if _event.is_action_pressed("jump"):
		if coyote_timer > 0:
			player.jump_count = 0
			return jump 
		elif player.jump_count <= 1 and player.double_jump:
			return jump
		else:
			buffer_timer = jump_buffer_time
	return next_state
	
	
#在这个状态下，每个过程tick会发生什么
func process(_delta: float) -> PlayerState:
	coyote_timer -= _delta
	buffer_timer -= _delta
	fall_timer += _delta
	if land_lock_timer <= 0:
		set_jump_frame()
	return next_state


#在这个状态下，每个物理过程tick会发生什么
func physics_process(_delta: float) -> PlayerState:
	if player.is_on_floor():
		#长下落落地恢复中：0.5秒不能移动
		if land_lock_timer > 0:
			player.velocity.x = 0
			land_lock_timer -= _delta
			if land_lock_timer <= 0:
				return idle
			return next_state
		VisualEffects.land_dust( player.global_position )
		#长下落落地：播放land动画、音频更大声，锁定结束后回到idle
		if fall_timer > long_fall_time:
			player.animation_player.play( "land" )
			Audio.play_spatial_sound( LAND , player.global_position , long_fall_land_volume , true , 0.5 )
			land_lock_timer = land_lock_time
			player.velocity.x = 0
			return next_state
		#player.add_debug_indicator(  )
		if buffer_timer > 0:
			player.jump_count = 0
			return jump
		return idle
	player.velocity.x = player.direction.x * player.move_speed
	return next_state



func set_jump_frame() -> void:
	var frame : float = remap( player.velocity.y , 0.0 , player.max_fall_velocity , 0.5 , 1.0 )
	#下落前期使用jump动画0.5~0.7秒，之后切换到fall循环动画直到落地
	if frame >= 0.7:
		if player.animation_player.current_animation != "fall":
			player.animation_player.play( "fall" )
	else:
		player.animation_player.seek( frame , true )
	pass
