class_name PlayerCamera extends Camera2D

#下蹲观察（Hollow Knight 式）：站在地面按住下键下蹲时，镜头整体下移一段距离看到脚下，
#松开后平移回原位。下移量以角色身高为参照（本项目角色高约 52px：CollisionStand 胶囊高 53）。
#镜头基准在脚底上方 48（player.tscn 里 Camera2D 的 position 为 (0,-48)），视口高 360，
#所以下移前画面下沿在脚底 +132 处、下移 60 后到脚底 +192，比原来多露出约一个角色身高。
#想再调幅度直接改这个值即可（改完在关卡里按着下键看脚下露出的量）。
@export_range( 0 , 160 , 4 , "suffix:px" ) var look_down_distance : float = 60.0
#下移与复位的过渡时长：走补间平滑插值，不做瞬间跳变
@export_range( 0.05 , 1.0 , 0.05 , "suffix:s" ) var look_down_time : float = 0.25

var shake_strengh : float = 0.0
var shake_time_left : float = 0.0
var shake_duration : float = 0.0

@export var max_shake_offset : float = 15.0
@export var default_shake_duration : float = 0.25

#镜头基准位置（相对玩家的默认偏移，即 player.tscn 里配的 (0,-48)），下移前的复位目标
var _base_position : Vector2 = Vector2.ZERO
#当前是否处于下蹲观察状态
var _look_down : bool = false
var _look_tween : Tween = null




func _ready() -> void:
	_base_position = position
	VisualEffects.camera_shook.connect( _apply_shake )
	SceneManager.new_scene_ready.connect( _on_scene_transition )
	pass


func _process( delta: float ) -> void:
	update_look_down()
	#时间驱动的确定性抖动：时长固定，振幅随剩余时间线性衰减
	#旧实现用 lerp(strength,0,rate*delta) 指数衰减，帧率相关且 weight>1 时强度翻负导致时长异常
	if shake_time_left > 0.0:
		shake_time_left = maxf( shake_time_left - delta , 0.0 )
		var envelope : float = shake_time_left / shake_duration
		offset = Vector2(
			randf_range( -shake_strengh , shake_strengh ),
			randf_range( -shake_strengh , shake_strengh )
		) * envelope
	else:
		offset = Vector2.ZERO
		shake_strengh = 0.0
		shake_duration = 0.0
	pass


func _apply_shake( strength : float , duration : float ) -> void:
	#取最大值而非覆盖：新触发不会截断/重置正在进行的更强抖动，连续触发时长封顶
	shake_strengh = maxf( shake_strengh , minf( strength , max_shake_offset ) )
	shake_duration = maxf( shake_duration , duration )
	shake_time_left = maxf( shake_time_left , duration )
	pass


#下蹲观察的触发条件：按住下键 + 站在地面 + 处于待机/跑动/下蹲这类常规地面状态。
#空中（Jump/Fall）、下蹲攻击（Attack）、冲刺/砸地/爬墙/受击/死亡等其他状态一律不下移。
#状态由玩家的状态机权威决定，所以下蹲中按攻击键起手时会立刻复位、攻击结束回到下蹲再平滑下移。
func update_look_down() -> void:
	var active : bool = false
	var player := get_parent() as Player
	if player != null and player.is_on_floor() and player.direction.y > 0.5:
		var st : PlayerState = player.current_state
		active = st is PlayerStateIdle or st is PlayerStateRun or st is PlayerStateCrouch
	if active == _look_down:
		return
	_look_down = active
	_tween_look_down()
	pass


#下移/复位一律走补间，挂在镜头自己身上；重新触发时先杀掉上一条补间，从当前位置继续
func _tween_look_down() -> void:
	if _look_tween != null and _look_tween.is_valid():
		_look_tween.kill()
	var target_y : float = _base_position.y + ( look_down_distance if _look_down else 0.0 )
	if is_equal_approx( position.y , target_y ):
		return
	_look_tween = create_tween()
	_look_tween.set_trans( Tween.TRANS_SINE ).set_ease( Tween.EASE_IN_OUT )
	_look_tween.tween_property( self , "position:y" , target_y , look_down_time )
	pass


func _on_scene_transition( _t , _o ) -> void:
	#切场景时把下蹲观察收回基准位置：新关卡从常规视角开始，避免读档/换关后镜头停在下方
	if _look_tween != null and _look_tween.is_valid():
		_look_tween.kill()
	_look_tween = null
	_look_down = false
	position.y = _base_position.y
	reset_smoothing.call_deferred()
	pass
