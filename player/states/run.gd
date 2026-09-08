@icon( "res://general/icons/state.svg" )
class_name PlayerStateRun extends PlayerState

@onready var sprite_2d: Sprite2D = $"../../Sprite2D"
@onready var sprite_2d_2: Sprite2D = $"../../Sprite2D2"
@onready var sprite_2d_3: Sprite2D = $"../../Sprite2D3"

#是否正在播放转向动画
var turning : bool = false

#离开run后0.2秒内按反方向键仍可播放转向动画的窗口时长(毫秒)
const TURN_INPUT_WINDOW_MSEC : int = 200
#离开run状态时的朝向与离开时间，供idle状态判断转向
var exit_direction : float = 0.0
var exit_time_msec : int = 0
#从idle进入时是否需要播放转向动画
var turn_on_enter : bool = false

#状态初始化时做什么
func init() -> void:
	pass
	
#当我们进入这个状态时会发生什么
func enter() -> void:
	#动画
	sprite_2d_2.visible = false
	sprite_2d_3.visible = false
	if turn_on_enter:
		#从idle松开方向键0.2秒内按反方向键进入，播放转向动画
		turn_on_enter = false
		_start_turn( exit_direction > 0 )
	else:
		sprite_2d.visible = true
		player.animation_player.play( "run" )
	pass
	
#当我们退出这个状态会发生什么
func exit() -> void:
	sprite_2d.visible = false
	sprite_2d_2.visible = true
	turning = false
	sprite_2d_3.visible = false
	#记录离开时间，供idle判断0.2秒内按反方向键
	exit_time_msec = Time.get_ticks_msec()
	pass

#按下输入会发生什么
func handle_input( _event : InputEvent ) -> PlayerState:
	#处理输入：向左跑时按右，向右跑时按左，播放转向动画
	if not turning and player.direction.x < 0 and _event.is_action_pressed( "right" ):
		_start_turn( false )
		return next_state
	if not turning and player.direction.x > 0 and _event.is_action_pressed( "left" ):
		_start_turn( true )
		return next_state
	if _event.is_action_pressed( "dash" ) and player.can_dash():
		return dash
	if _event.is_action_pressed("attack"):
		return attack
	if _event.is_action_pressed("jump"):
		return jump
	return next_state


#开始转向动画，flip 为转向后的朝向是否镜像
func _start_turn( flip : bool ) -> void:
	turning = true
	sprite_2d_3.visible = true
	sprite_2d_3.flip_h = flip
	sprite_2d.visible = false
	player.animation_player.play( "turn" )
	
	
#在这个状态下，每个过程tick会发生什么
func process(_delta: float) -> PlayerState:
	if turning:
		#转向动画播完后恢复跑步画面
		if not player.animation_player.is_playing():
			turning = false
			sprite_2d_3.visible = false
			sprite_2d.visible = true
			player.animation_player.play( "run" )
		return next_state
	if player.direction.x == 0:
		return idle
	elif player.direction.y > 0.5:
		return crouch
	return next_state


#在这个状态下，每个物理过程tick会发生什么
func physics_process(_delta: float) -> PlayerState:
	player.velocity.x = player.direction.x * player.move_speed
	#记录当前跑动朝向，供idle判断转向
	if player.direction.x != 0:
		exit_direction = signf( player.direction.x )
	if player.is_on_floor() == false:
		return fall
	return next_state
