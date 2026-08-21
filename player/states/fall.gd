class_name PlayerStateFall extends PlayerState

@export var fal_gravity_mulitplier : float = 1.165
@export var coyote_time : float = 0.125
@export var jump_buffer_time : float = 0.2

var coyote_timer : float = 0
var buffer_timer : float = 0

#状态初始化时做什么
func init() -> void:
	pass
	
#当我们进入这个状态时会发生什么
func enter() -> void:
	#动画
	player.animation_player.play( "jump" )
	player.animation_player.pause()
	player.gravity_mulitplier = fal_gravity_mulitplier
	if player.previous_state == idle or player.previous_state == run or player.previous_state == crouch:
		coyote_timer = coyote_time
	else:
		coyote_timer = 0
	pass
	
#当我们退出这个状态会发生什么
func exit() -> void:
	player.gravity_mulitplier = 1.0
	buffer_timer = 0
	pass

#按下输入会发生什么
func handle_input( _event : InputEvent ) -> PlayerState:
	#处理输入
	if _event.is_action_pressed("attack"):
		return attack
	if _event.is_action_pressed("jump"):
		if coyote_timer > 0:
			return jump 
		else:
			buffer_timer = jump_buffer_time
	return next_state
	
	
#在这个状态下，每个过程tick会发生什么
func process(_delta: float) -> PlayerState:
	coyote_timer -= _delta
	buffer_timer -= _delta
	set_jump_frame()
	return next_state


#在这个状态下，每个物理过程tick会发生什么
func physics_process(_delta: float) -> PlayerState:
	if player.is_on_floor():
		VisualEffects.land_dust( player.global_position )
		#player.add_debug_indicator(  )
		if buffer_timer > 0:
			return jump 
		return idle
	player.velocity.x = player.direction.x * player.move_speed
	return next_state



func set_jump_frame() -> void:
	var frame : float = remap( player.velocity.y , 0.0 , player.max_fall_velocity , 0.5 , 1.0 )
	player.animation_player.seek( frame,true )
	pass
