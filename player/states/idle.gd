class_name PlayerStateIdle extends PlayerState

@onready var sprite_2d: Sprite2D = $"../../Sprite2D"
@onready var sprite_2d_2: Sprite2D = $"../../Sprite2D2"


#状态初始化时做什么
func init() -> void:
	pass
	
	
#当我们进入这个状态时会发生什么
func enter() -> void:
	#动画
	sprite_2d.visible = false
	sprite_2d_2.visible = true
	player.animation_player.play( "idle_2" )
	player.jump_count = 0
	player.dash_count = 0
	pass
	
#当我们退出这个状态会发生什么
func exit() -> void:
	pass

#按下输入会发生什么
func handle_input( _event : InputEvent ) -> PlayerState:
	#处理输入
	#松开方向键进入idle后0.2秒内按反方向键，进入run时播放转向动画
	if _event.is_action_pressed( "left" ) or _event.is_action_pressed( "right" ):
		var press_dir : float = -1.0 if _event.is_action_pressed( "left" ) else 1.0
		var time_since_run : int = Time.get_ticks_msec() - run.exit_time_msec
		if run.exit_direction != 0 and press_dir == -run.exit_direction and time_since_run <= run.TURN_INPUT_WINDOW_MSEC:
			run.turn_on_enter = true
			return run
	if _event.is_action_pressed( "dash" ) and player.can_dash():
		return dash
	if _event.is_action_pressed("attack"):
		return attack
	if _event.is_action_pressed("jump"):
		return jump
	return null
	
	
#在这个状态下，每个过程tick会发生什么
func process(_delta: float) -> PlayerState:
	if player.direction.x != 0:
		return run
	elif player.direction.y > 0.5:
		return crouch
	return null


#在这个状态下，每个物理过程tick会发生什么
func physics_process(_delta: float) -> PlayerState:
	player.velocity.x = 0
	if player.is_on_floor() == false:
		return fall	
	return next_state
