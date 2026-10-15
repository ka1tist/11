class_name PlayerCamera extends Camera2D

#下蹲观察（Hollow Knight 式）：站在地面按住下键下蹲时，镜头整体下移一段距离看到脚下，
#松开后平移回原位。下移量以角色身高为参照（本项目角色高约 52px：CollisionStand 胶囊高 53）。
#镜头基准在脚底上方 48（player.tscn 里 Camera2D 的 position 为 (0,-48)），视口高 360，
#所以下移前画面下沿在脚底 +132 处、下移 60 后到脚底 +192，比原来多露出约一个角色身高。
#想再调幅度直接改这个值即可（改完在关卡里按着下键看脚下露出的量）。
@export_range( 0 , 160 , 4 , "suffix:px" ) var look_down_distance : float = 60.0
#下移与复位的过渡时长：走缓动插值，不做瞬间跳变
@export_range( 0.05 , 1.0 , 0.05 , "suffix:s" ) var look_down_time : float = 0.25

#击败 BOSS 聚焦期间的摄影机跟随速度：平时是 player.tscn 里配的 5，聚焦时要"咬住"目标，
#临时提到 60 —— 慢动作会把 delta 缩到 0.25，折算过来仍约 0.1 秒收敛，镜头不会追不上聚焦点
@export var focus_smoothing_speed : float = 60.0

#击败 BOSS 聚焦期间的放大倍率：在关卡当前 zoom 的基础上再乘这个系数（1 = 不放大）。
#取 1.6 兼顾两件事：① BOSS 精灵在 640x360 里占宽约 192px，明显推近；② 视野下沿刚好处在
#关卡底边之内而镜头中心已能压到 BOSS 精灵中心附近，所以贴着地面倒下的 BOSS 也能落在画面中央
@export_range( 1.0 , 3.0 , 0.05 ) var focus_zoom : float = 1.6

var shake_strengh : float = 0.0
var shake_time_left : float = 0.0
var shake_duration : float = 0.0

@export var max_shake_offset : float = 15.0
@export var default_shake_duration : float = 0.25

#镜头基准位置（相对玩家的默认偏移，即 player.tscn 里配的 (0,-48)）
var _base_position : Vector2 = Vector2.ZERO
#摄影机原本的跟随速度，聚焦结束后原样恢复
var _base_smoothing_speed : float = 5.0
#关卡当前的基础 zoom（由 LevelBounds 按关卡尺寸设定，多为 1）；未聚焦时每帧同步，聚焦时按它放大
var _base_zoom : Vector2 = Vector2.ONE

#下蹲观察：下移进度的归一化权重（0 = 基准视角，1 = 下移到位）。
#这里存权重而不是直接补间 position.y，是为了能和击败聚焦叠加——两者都要改写镜头位置，
#各自补间同一个 position 会互相打架，统一改成每帧按权重合成
var _look_blend : float = 0.0
var _look_target : float = 0.0

#击败聚焦：目标世界坐标 + 混合权重（0 = 纯跟随玩家，1 = 完全锁定在目标上）
var _focus_position : Vector2 = Vector2.ZERO
var _focus_blend : float = 0.0
var _focus_target : float = 0.0
#权重推进速度（每秒），由聚焦 / 回归时长换算
var _focus_in_speed : float = 4.0
var _focus_out_speed : float = 2.0
#是否处于"聚焦专用的高跟随速度"状态
var _focus_boosted : bool = false


func _ready() -> void:
	_base_position = position
	_base_smoothing_speed = position_smoothing_speed
	_base_zoom = zoom
	VisualEffects.camera_shook.connect( _apply_shake )
	VisualEffects.camera_focused.connect( _on_focus_requested )
	VisualEffects.camera_focus_released.connect( _on_focus_released )
	SceneManager.new_scene_ready.connect( _on_scene_transition )
	pass


func _process( delta: float ) -> void:
	#真实秒数：慢动作（击败 BOSS 时全局 time_scale 降到 0.25）会把 _process 的 delta 一起缩放，
	#镜头的下蹲位移 / 聚焦回归 / 震屏一律按真实秒数推进，否则 0.6 秒震屏会被拉成 2.4 秒、镜头回归也被拖慢
	var real_delta : float = delta / maxf( Engine.time_scale , 0.001 )
	update_look_down( real_delta )
	update_focus( real_delta )
	update_shake( real_delta )
	_apply_position()
	pass


func _apply_shake( strength : float , duration : float ) -> void:
	#取最大值而非覆盖：新触发不会截断/重置正在进行的更强抖动，连续触发时长封顶
	shake_strengh = maxf( shake_strengh , minf( strength , max_shake_offset ) )
	shake_duration = maxf( shake_duration , duration )
	shake_time_left = maxf( shake_time_left , duration )
	pass


#时间驱动的确定性抖动：时长固定，振幅随剩余时间线性衰减
#旧实现用 lerp(strength,0,rate*delta) 指数衰减，帧率相关且 weight>1 时强度翻负导致时长异常
func update_shake( real_delta : float ) -> void:
	if shake_time_left > 0.0:
		shake_time_left = maxf( shake_time_left - real_delta , 0.0 )
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


#下蹲观察的触发条件：按住下键 + 站在地面 + 处于待机/跑动/下蹲这类常规地面状态。
#空中（Jump/Fall）、下蹲攻击（Attack）、冲刺/砸地/爬墙/受击/死亡等其他状态一律不下移。
#状态由玩家的状态机权威决定，所以下蹲中按攻击键起手时会立刻复位、攻击结束回到下蹲再平滑下移。
func update_look_down( real_delta : float ) -> void:
	var active : bool = false
	var player := get_parent() as Player
	if player != null and player.is_on_floor() and player.direction.y > 0.5:
		var st : PlayerState = player.current_state
		active = st is PlayerStateIdle or st is PlayerStateRun or st is PlayerStateCrouch
	_look_target = 1.0 if active else 0.0
	if is_equal_approx( _look_blend , _look_target ):
		return
	#按真实秒数在 look_down_time 内走完 0→1，实际位移再用 smoothstep 映射成缓入缓出
	_look_blend = move_toward( _look_blend , _look_target , real_delta / maxf( look_down_time , 0.01 ) )
	pass


#聚焦权重推进：推入 / 回归分别用各自的时长，权重本身线性走、位移由 _ease_in_out 缓动
func update_focus( real_delta : float ) -> void:
	if _focus_blend != _focus_target:
		var speed : float = _focus_in_speed if _focus_target > _focus_blend else _focus_out_speed
		_focus_blend = move_toward( _focus_blend , _focus_target , speed * real_delta )
	elif _focus_boosted:
		#聚焦已结束、权重归零：镜头此刻正停在玩家跟随位置上，改回常规跟随速度不会产生跳变
		_focus_boosted = false
		position_smoothing_speed = _base_smoothing_speed
		#把聚焦期间的放大收回关卡的基础 zoom（此刻权重已归零，这里写的是与合成结果相同的值，不会跳）
		zoom = _base_zoom
	pass


#每帧合成镜头的位置与缩放：跟随分量（玩家位置 + 基准偏移 + 下蹲下移）与聚焦分量按缓动权重混合，
#缩放同时从关卡基础 zoom 平滑放大到 zoom*focus_zoom（视野收窄，BOSS 在画面里更大）。
#位置写在本地 position 上而不是 global_position：父节点（玩家根）带 x 镜像缩放时也能自动对齐；
#zoom 则每帧由这里写入，聚焦期间会盖过 LevelBounds 对 zoom 的重设（击败当帧会重算一次），
#所以镜头不会在放大途中被拽回 1.0
func _apply_position() -> void:
	var parent := get_parent() as Node2D
	if parent == null:
		return
	var follow : Vector2 = _base_position + Vector2( 0.0 , look_down_distance * _ease_in_out( _look_blend ) )
	if _focus_blend > 0.0:
		#注意用父节点的 to_local：本节点的 to_local 是相对自身的，取不到目标位置的本地坐标
		var t : float = _ease_in_out( _focus_blend )
		position = follow.lerp( parent.to_local( _focus_position ) , t )
		#放大：视野越小，镜头可见范围越窄，BOSS 越靠近画面中心（同时贴着关卡边界时也更容易居中）
		zoom = _base_zoom.lerp( _base_zoom * focus_zoom , t )
	else:
		position = follow
		#未聚焦期间完全不动 zoom：关卡（LevelBounds）按自身尺寸设定的 zoom 归它管，镜头只在聚焦期间临时放大
		pass


#缓入缓出（smoothstep）：所有位移都过这一层缓动，起停处没有速度突变
func _ease_in_out( t : float ) -> float:
	return t * t * ( 3.0 - 2.0 * t )


#镜头聚焦到某个世界坐标（击败 BOSS 时锁定它倒下的位置）：in_time 内平滑推入，
#之后由 release_focus 按 out_time 平滑回到玩家跟随状态
func focus_on( world_pos : Vector2 , in_time : float , out_time : float ) -> void:
	_focus_position = world_pos
	_focus_in_speed = 1.0 / maxf( in_time , 0.01 )
	_focus_out_speed = 1.0 / maxf( out_time , 0.01 )
	#记下本次聚焦前关卡的基础 zoom，聚焦结束后按它还原（只在没在聚焦时才记，避免把放大中的值当成基准）
	if _focus_blend <= 0.0:
		_base_zoom = zoom
	#从 0 开始推入：权重 0 就是当前的跟随位置，所以第一帧不会跳
	_focus_blend = 0.0
	_focus_target = 1.0
	#聚焦期间临时提高跟随速度，让画面真正咬住聚焦点（否则慢动作下平滑跟随后会一直落在目标后面）
	if not _focus_boosted:
		_focus_boosted = true
		position_smoothing_speed = maxf( _base_smoothing_speed , focus_smoothing_speed )
	pass


#结束聚焦：权重平滑归零，镜头逐步回到玩家跟随状态
func release_focus() -> void:
	_focus_target = 0.0
	pass


func _on_focus_requested( world_pos : Vector2 , in_time : float , out_time : float ) -> void:
	focus_on( world_pos , in_time , out_time )
	pass


func _on_focus_released() -> void:
	release_focus()
	pass


func _on_scene_transition( _t , _o ) -> void:
	#切场景时把下蹲观察与聚焦一并收回：新关卡从常规视角开始，避免读档/换关后镜头停在下方或锁在旧位置
	_look_blend = 0.0
	_look_target = 0.0
	_focus_blend = 0.0
	_focus_target = 0.0
	if _focus_boosted:
		_focus_boosted = false
		position_smoothing_speed = _base_smoothing_speed
	position = _base_position
	#聚焦若在新场景淡入前被打断，放大倍率可能还停在中途，一并收回基础 zoom
	zoom = _base_zoom
	reset_smoothing.call_deferred()
	pass
