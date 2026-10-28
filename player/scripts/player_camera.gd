class_name PlayerCamera extends Camera2D

#像素网格对齐模块：用 preload 取脚本而不是依赖全局类名注册，
#这样即使编辑器的全局类缓存还没刷到新文件，本脚本也能正常编译
const PixelGrid := preload( "res://00_global/pixel_grid.gd" )

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
#手动平滑后的镜头位置（本地坐标，未取整）：引擎自带的 position_smoothing 会输出亚像素位置，
#配合 rendering/2d/snap/snap_2d_transforms_to_pixel 时整屏会在相邻像素间来回跳，改由本脚本平滑
var _smooth_position : Vector2 = Vector2.ZERO
#聚焦推入时的起始缩放：从当前缩放接续（聚焦接管演出序列时缩放可能已放大），避免缩放跳变
var _focus_zoom_from : Vector2 = Vector2.ONE
#聚焦推入时的起始世界位置：为真时从它起步（聚焦接管序列/中途重新聚焦），否则从玩家跟随位置起步
var _focus_entry_world : Vector2 = Vector2.ZERO
var _focus_entry_valid : bool = false

#演出（视频）序列镜头允许的过渡时长区间：短于 0.3 秒显生硬，长于 0.8 秒节奏拖沓。
#所有对外接口的 duration 都会被 clamp 到这个区间
const SEQUENCE_TIME_MIN : float = 0.3
const SEQUENCE_TIME_MAX : float = 0.8
#演出序列的镜头状态：0 = 无；1 = 平滑推入后保持；2 = 平滑回归玩家
var _seq_phase : int = 0
#推入起点 / 目标（世界坐标，均为整数像素）
var _seq_push_from : Vector2 = Vector2.ZERO
var _seq_target : Vector2 = Vector2.ZERO
#回归起点（世界坐标），支持在推入途中提前 release
var _seq_release_from : Vector2 = Vector2.ZERO
#0→1 的过渡进度；位移再经 _ease_in_out 映射成缓入缓出
var _seq_blend : float = 0.0
var _seq_duration : float = 0.5
#推入 / 回归的起始缩放与目标缩放（目标缩放已经过 PixelGrid.quantize_zoom，保证整数倍）
var _seq_zoom_from : Vector2 = Vector2.ONE
var _seq_zoom_to : Vector2 = Vector2.ONE
var _seq_release_zoom_from : Vector2 = Vector2.ONE


func _ready() -> void:
	_base_position = position
	_base_smoothing_speed = position_smoothing_speed
	_base_zoom = zoom
	_smooth_position = position
	#校验像素对齐前提（对齐开关缺失会被补上；纹理过滤异常只告警）
	PixelGrid.ensure_constraints()
	#关闭引擎自带平滑，改为本脚本手动平滑后把落点对齐到整像素：
	#项目开着 rendering/2d/snap/snap_2d_transforms_to_pixel，亚像素的镜头位置会让整屏绘制
	#在相邻像素之间反复跳（静止/贴边时尤其明显，表现为整屏 1px 抖动）
	position_smoothing_enabled = false
	VisualEffects.camera_shook.connect( _apply_shake )
	VisualEffects.camera_focused.connect( _on_focus_requested )
	VisualEffects.camera_focus_released.connect( _on_focus_released )
	VisualEffects.camera_sequence_started.connect( _on_sequence_started )
	VisualEffects.camera_sequence_released.connect( _on_sequence_released )
	SceneManager.new_scene_ready.connect( _on_scene_transition )
	pass


func _process( delta: float ) -> void:
	#真实秒数：慢动作（击败 BOSS 时全局 time_scale 降到 0.25）会把 _process 的 delta 一起缩放，
	#镜头的下蹲位移 / 聚焦回归 / 序列过渡 / 震屏一律按真实秒数推进，否则 0.6 秒震屏会被拉成 2.4 秒、镜头回归也被拖慢
	var real_delta : float = delta / maxf( Engine.time_scale , 0.001 )
	update_look_down( real_delta )
	update_focus( real_delta )
	update_sequence( real_delta )
	update_shake( real_delta )
	_apply_position( real_delta )
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
		#震屏偏移也取整：offset 会并入最终画布变换，留小数就等于每帧给整屏加了亚像素偏移
		offset = PixelGrid.align_position( Vector2(
			randf_range( -shake_strengh , shake_strengh ),
			randf_range( -shake_strengh , shake_strengh )
		) * envelope )
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


#每帧合成镜头的位置与缩放，优先级：演出序列 > 击败聚焦 > 常规跟随。
#位置一律以「世界坐标」合成，最后转回本地并取整：本节点挂在玩家根上，玩家根的缩放/旋转
#（含 x 镜像）会自动抵消，不会把镜头带偏。
#平滑由本脚本执行（引擎平滑已关闭），落点经 PixelGrid.align_position 对齐到整像素：
#整数画布变换才能让开启整像素对齐的整屏绘制稳定，不会在相邻像素间来回跳。
func _apply_position( delta : float ) -> void:
	var parent := get_parent() as Node2D
	if parent == null:
		return
	#常规跟随状态（无聚焦/无序列）时同步关卡的基础 zoom：LevelBounds 可能按关卡尺寸重设 zoom
	if _seq_phase == 0 and _focus_blend <= 0.0 and _focus_target <= 0.0:
		_base_zoom = zoom
	var follow : Vector2 = _base_position + Vector2( 0.0 , look_down_distance * _ease_in_out( _look_blend ) )
	var follow_world : Vector2 = parent.to_global( follow )

	#演出序列：路径本身就是缓入缓出，不再叠一层指数平滑（否则实际到位时间会被拉长，与 0.3~0.8 秒的约定不符）
	if _seq_phase != 0:
		var t : float = _ease_in_out( _seq_blend )
		var world : Vector2
		if _seq_phase == 1:
			world = _seq_push_from.lerp( _seq_target , t )
			#缩放不做连续插值：1x→2x 中间会出现 1.3/1.5 这类非整数倍，屏幕坐标必然落在亚像素上。
			#推入期间保持起始 zoom，到位后才切到目标 zoom（整数倍之间的一次性切换）
			zoom = _seq_zoom_to if _seq_blend >= 1.0 else _seq_zoom_from
		else:
			#回归目标每帧重算：玩家在演出期间可能仍在移动，镜头始终回到「当前」跟随点。
			#终点按「回归结束时的 zoom（基础 zoom）」钳制——缩放是硬切回基础值的，
			#若按放大中的视野钳制，切回时镜头中心会被多钳一次，产生跳变
			var release_target : Vector2 = PixelGrid.align_position(
				_clamp_to_limits( follow_world , _base_zoom ) )
			world = _seq_release_from.lerp( release_target , t )
			#回归期间保持起始 zoom，结束时由 update_sequence 一次性收回基础 zoom
			zoom = _seq_release_zoom_from
		_smooth_position = parent.to_local( world )
		#position 存的是本地坐标：世界坐标取整后再转回本地（父节点带位移/镜像，不能直接写世界值）
		position = parent.to_local( PixelGrid.align_position( parent.to_global( _smooth_position ) ) )
		return

	var desired : Vector2 = follow
	if _focus_blend > 0.0:
		var t : float = _ease_in_out( _focus_blend )
		#推入：从「实际起始位置」接续（首次聚焦时就是玩家跟随位置，行为与原来一致）
		var from : Vector2 = _focus_entry_world if _focus_entry_valid else follow_world
		desired = parent.to_local( from.lerp( _focus_position , t ) )
		#放大：视野越小，镜头可见范围越窄，BOSS 越靠近画面中心（同时贴着关卡边界时也更容易居中）。
		#推入从当前缩放接续，回归保持原公式（t 递减回基础 zoom）
		if _focus_target > _focus_blend:
			zoom = _focus_zoom_from.lerp( _base_zoom * focus_zoom , t )
		else:
			zoom = _base_zoom.lerp( _base_zoom * focus_zoom , t )
	#与引擎平滑同样的指数收敛；聚焦期间用更高的跟随速度（速度为 0 时直接跟随）
	var speed : float = focus_smoothing_speed if _focus_boosted else _base_smoothing_speed
	var weight : float = 1.0 - exp( -speed * delta ) if speed > 0.0 else 1.0
	#大位移（关卡瞬移/传送/序列接管）直接跟上，避免镜头慢慢爬过去
	if desired.distance_to( _smooth_position ) > 200.0:
		weight = 1.0
	_smooth_position = _smooth_position.lerp( desired , clampf( weight , 0.0 , 1.0 ) )
	#position 存的是本地坐标：世界坐标取整后再转回本地
	position = parent.to_local( PixelGrid.align_position( parent.to_global( _smooth_position ) ) )
	pass


#演出序列的进度推进：推入到达 1 后停在目标上保持（等演出停留结束再 release）；
#回归到达 1 后结束序列，回到常规跟随（此刻 _smooth_position 已经等于跟随点，不会跳）
func update_sequence( real_delta : float ) -> void:
	if _seq_phase == 0:
		return
	_seq_blend = minf( _seq_blend + real_delta / maxf( _seq_duration , 0.01 ) , 1.0 )
	if _seq_phase == 2 and _seq_blend >= 1.0:
		_seq_phase = 0
		zoom = _base_zoom
	pass


#缓入缓出（smoothstep）：所有位移都过这一层缓动，起停处没有速度突变
func _ease_in_out( t : float ) -> float:
	return t * t * ( 3.0 - 2.0 * t )


#镜头聚焦到某个世界坐标（击败 BOSS 时锁定它倒下的位置）：in_time 内平滑推入，
#之后由 release_focus 按 out_time 平滑回到玩家跟随状态
func focus_on( world_pos : Vector2 , in_time : float , out_time : float ) -> void:
	#接管正在进行的演出序列 / 中途重新聚焦：从当前实际位置与缩放接续，不回到跟随点、也不跳变
	if _seq_phase != 0 or _focus_blend > 0.0:
		_focus_entry_world = camera_world_center()
		_focus_entry_valid = true
		_focus_zoom_from = zoom
		_seq_phase = 0
		_seq_blend = 0.0
	else:
		_focus_entry_valid = false
		_base_zoom = zoom
		_focus_zoom_from = _base_zoom
	_focus_position = world_pos
	_focus_in_speed = 1.0 / maxf( in_time , 0.01 )
	_focus_out_speed = 1.0 / maxf( out_time , 0.01 )
	#从 0 开始推入：权重 0 就是当前的跟随/起始位置，所以第一帧不会跳
	_focus_blend = 0.0
	_focus_target = 1.0
	#聚焦期间临时提高跟随速度，让画面真正咬住聚焦点（否则慢动作下平滑跟随后会一直落在目标后面）
	if not _focus_boosted:
		_focus_boosted = true
		position_smoothing_speed = maxf( _base_smoothing_speed , focus_smoothing_speed )
	pass


#region /// 演出（视频）序列镜头

#当前镜头的实际世界中心（已平滑、未取整）：演出序列与聚焦都从它接续，保证任何时刻接管都不跳
func camera_world_center() -> Vector2:
	var parent := get_parent() as Node2D
	if parent == null:
		return global_position
	return parent.to_global( _smooth_position )


#演出镜头推入：从「当前镜头位置」在 duration 秒内平滑移到 world_pos，到达后保持锁定，
#直到调用 camera_sequence_release() 才平滑回到玩家跟随。
#duration 会被限制在 0.3~0.8 秒；zoom_level 是相对基础 zoom 的整数倍（如 1 = 不缩放，2 = 放大一倍），
#非整数倍会被 PixelGrid 量化掉——整数倍缩放是像素网格严格对齐的前提。
#缩放不做连续过渡（中间值必产生亚像素），而是在推入到位的那一帧一次性切到目标倍数。
func camera_sequence_to( world_pos : Vector2 , duration : float = 0.5 , zoom_level : float = 1.0 ) -> void:
	#先算起点（此时若正在聚焦，zoom 可能处于放大途中，_base_zoom 仍是被记录的基础值）
	_seq_push_from = camera_world_center()
	_seq_zoom_from = zoom
	if _seq_phase == 0 and _focus_blend <= 0.0:
		_base_zoom = zoom
	_seq_zoom_to = PixelGrid.quantize_zoom( _base_zoom * maxf( zoom_level , 1.0 ) )
	#目标先钳到关卡镜头限位内：限位外的坐标引擎会直接钳死，那样序列「到位」的终点与目标不一致，
	#回归时也会多出一段被硬钳的位移
	_seq_target = PixelGrid.align_position( _clamp_to_limits( world_pos , _seq_zoom_to ) )
	_seq_duration = clampf( duration , SEQUENCE_TIME_MIN , SEQUENCE_TIME_MAX )
	_seq_blend = 0.0
	_seq_phase = 1
	#接管聚焦：直接终止聚焦状态（不走回归动画），序列从当前位置继续，画面不跳
	_cancel_focus()
	pass


#结束演出镜头：从当前位置在 duration 秒内平滑回到玩家跟随（duration 同样限制在 0.3~0.8 秒）。
#推入还没结束时调用也可以：会从当前半途位置直接开始回归
func camera_sequence_release( duration : float = 0.5 ) -> void:
	if _seq_phase == 0:
		return
	_seq_release_from = camera_world_center()
	_seq_release_zoom_from = zoom
	_seq_duration = clampf( duration , SEQUENCE_TIME_MIN , SEQUENCE_TIME_MAX )
	_seq_blend = 0.0
	_seq_phase = 2
	pass


#立即终止聚焦状态（不播放回归）：仅供序列 / 切场景等需要硬接管时使用
func _cancel_focus() -> void:
	_focus_blend = 0.0
	_focus_target = 0.0
	_focus_entry_valid = false
	if _focus_boosted:
		_focus_boosted = false
		position_smoothing_speed = _base_smoothing_speed
	pass


#把镜头中心钳制到关卡镜头限位内（与引擎的钳制公式一致：半视野 = 视口尺寸 / zoom * 0.5）。
#限位比视野还小时放弃钳制（否则上下限会交叉）
func _clamp_to_limits( world_pos : Vector2 , zoom_value : Vector2 ) -> Vector2:
	var half : Vector2 = get_viewport_rect().size / zoom_value * 0.5
	var min_center : Vector2 = Vector2( limit_left + half.x , limit_top + half.y )
	var max_center : Vector2 = Vector2( limit_right - half.x , limit_bottom - half.y )
	if min_center.x > max_center.x or min_center.y > max_center.y:
		return world_pos
	return world_pos.clamp( min_center , max_center )


func _on_sequence_started( world_pos : Vector2 , duration : float , zoom_level : float ) -> void:
	camera_sequence_to( world_pos , duration , zoom_level )
	pass


func _on_sequence_released( duration : float ) -> void:
	camera_sequence_release( duration )
	pass

#endregion


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
	#切场景时把下蹲观察 / 聚焦 / 演出序列一并收回：新关卡从常规视角开始，避免读档/换关后镜头停在下方或锁在旧位置
	_look_blend = 0.0
	_look_target = 0.0
	_focus_blend = 0.0
	_focus_target = 0.0
	_focus_entry_valid = false
	_seq_phase = 0
	_seq_blend = 0.0
	if _focus_boosted:
		_focus_boosted = false
		position_smoothing_speed = _base_smoothing_speed
	position = _base_position
	#手动平滑的状态同步复位：新关卡第一帧就落在玩家身上，不会从上一关的位置滑过来
	_smooth_position = _base_position
	#聚焦若在新场景淡入前被打断，放大倍率可能还停在中途，一并收回基础 zoom
	zoom = _base_zoom
	offset = Vector2.ZERO
	reset_smoothing.call_deferred()
	pass
