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
	
	# 土狼时间只给“确实刚从地面走下来”的情况。previous_state 是刚离开的那个状态，
	# 跳跃/下落中途经攻击等中间状态再回到 fall 时，它会被中间状态顶掉，
	# 用“非 jump/run/dash 就给土狼时间”的黑名单写法会漏判，空中白送一次跳跃。
	# 因此改为白名单：站在地面时地面消失（idle）或助跑走下落差（run）才给——
	# run 只能从 idle 进入，而 idle 会把 jump_count 清零，两种情况玩家都还没用过跳跃；
	# 新增状态默认落到 else，不会再出现空中误发土狼时间。
	var prev : PlayerState = player.previous_state
	if prev == idle or prev == run:
		coyote_timer = coyote_time
	else:
		coyote_timer = 0
		if prev == crouch:
			#蹲着走下落差：消耗掉地面跳
			player.jump_count = 1
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
			#土狼跳：宽限期内补的是"本段滞空的第一跳"（jump_count 归零 → do_jump 走地面跳分支），
			#coyote_timer 只在刚从地面走落时才 > 0，空中不会有宽限期
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
	#贴墙进入爬墙：能力已解锁、正按向墙面，且已越过跳跃最高点（上升途中不接，见 get_wall_climb_side）。
	#无论长按跳满高度、短按松键提前转入 fall，还是空中下坠，都在这里统一接墙
	if player.get_wall_climb_side() != 0:
		return wall_climb
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
