extends Node

const DUST_EFFECT = preload("uid://qs2i4ldiy3hl")
const HIT_PARTICLES = preload("uid://w5vvcvi053qg")

#BOSS 特效表：640x384 = 5列x3行，单帧 128x128
const BOSS_EFFECTS = preload("res://bosses/01/sprites/pink_box_effects.png")
const BOSS_EFFECTS_COLUMNS : int = 5
const BOSS_EFFECTS_ROWS : int = 3
#BOSS 一次性特效的默认绘制层（仅在调用方没给参照对象时使用）：取 1。
#VisualEffects 是 autoload、先于当前场景挂到 /root，同层时按树序绘制，所以特效排在场景里的节点之后
#（不遮挡 BOSS），同时仍高于 0 层的关卡背景与地面（不抬高就会被不透明视差背景盖住，07 关即如此）。
#更稳的做法是把 BOSS 本体当参照对象传给 play_effect_row（见 play_effect 的 under 参数）：
#层号完全跟随该对象，关卡实例把它的 z_index 调成几层都不影响「特效在它之后、背景之前」的关系
const FX_Z_INDEX : int = 1
#特效表行首帧（行*列）：0=尖刺爆发 5=像素爆散 10=垂直消散
const FX_ROW_SPIKE : int = 0
const FX_ROW_BURST : int = 5
const FX_ROW_FADE : int = 10
#各行结束帧
const FX_ROW_SPIKE_END : int = 4
const FX_ROW_BURST_END : int = 9
const FX_ROW_FADE_END : int = 12
const FX_DEFAULT_FPS : float = 14.0


signal camera_shook( strength : float , duration : float )

#演出（视频/过场）序列镜头广播（PlayerCamera 接收）：
#推入 = 目标世界坐标 + 过渡时长（0.3~0.8 秒，越界会被限制）+ 相对基础 zoom 的整数倍缩放；
#回归 = 回到玩家跟随的过渡时长。任何演出脚本只需发这两个信号，不用持有 PlayerCamera 引用。
signal camera_sequence_started( world_pos : Vector2 , duration : float , zoom_level : float )
signal camera_sequence_released( duration : float )

#region /// 击败 BOSS 的聚焦慢动作

## 击败 BOSS 的演出（由死亡状态在击败判定帧调用一次，见 boss_defeat_focus）：
## 镜头推入并锁定它倒下的位置 + 全局 time_scale 慢动作 2 秒 + 四周暗角与身后光晕，结束后平滑恢复。

#镜头聚焦广播（PlayerCamera 接收）：目标世界坐标 + 推入 / 回归时长（真实秒数）
signal camera_focused( world_pos : Vector2 , in_time : float , out_time : float )
signal camera_focus_released()

#慢动作倍率（0.2~0.3 之间按手感微调：数值越小越慢）
const DEFEAT_FOCUS_TIME_SCALE : float = 0.25
#慢动作持续的真实秒数：慢动作期间 delta 会被缩放，计时必须用 ignore_time_scale 的计时器
const DEFEAT_FOCUS_HOLD : float = 2.0
#时间缩放从慢动作缓动回 1.0 的真实秒数
const DEFEAT_FOCUS_RESTORE : float = 0.5
#镜头推入 / 回归的时长（由 PlayerCamera 按真实秒数执行）；回归与时间缩放恢复同时开始
const DEFEAT_FOCUS_CAM_IN : float = 0.3
const DEFEAT_FOCUS_CAM_OUT : float = 0.6
#暗角遮罩最强时的不透明度：中心保持透明，只压暗四周，把视线收拢到 BOSS 身上。
#聚焦时画面会放大（PlayerCamera.focus_zoom），BOSS 又稳在画面中下偏中心处，
#所以内圈留得比较宽（见 DEFEAT_VIGNETTE_INNER），避免把 BOSS 本体也压暗
const DEFEAT_VIGNETTE_ALPHA : float = 0.45
#暗角直通透明的内圈半径占比（0~1）：这个比例以内不压暗，之后渐变到全黑
const DEFEAT_VIGNETTE_INNER : float = 0.72
#暗角 / 光晕的淡入时长（真实秒数）
const DEFEAT_VIGNETTE_FADE_IN : float = 0.3
#焦点光晕：叠在 BOSS 身后的柔和径向亮光（加色混合），峰值不透明度与世界半径
const DEFEAT_GLOW_ALPHA : float = 0.35
const DEFEAT_GLOW_RADIUS : float = 140.0

#本次聚焦演出是否在进行中（保证只触发一次）
var _defeat_focus_active : bool = false
#代次令牌：切场景或新的击败会让上一次的协程在 await 之后自动作废，两次演出不会互相踩
var _defeat_focus_token : int = 0
#常驻暗角遮罩（挂在本节点下；切场景时只重置透明度、不销毁）
var _defeat_vignette_layer : CanvasLayer
var _defeat_vignette : TextureRect
var _defeat_vignette_tween : Tween
#焦点光晕（挂在 BOSS 所在场景里，随场景一起被销毁）
var _defeat_glow : Sprite2D
var _defeat_glow_tween : Tween
#endregion


func _ready() -> void:
	#切换地图时清空残留特效：灰尘/粒子挂在autoload节点上会跨场景存活，
	#暂停期间被冻结、新地图淡入后继续播完，导致上一个地图的特效出现在新地图
	SceneManager.load_scene_started.connect( clear_effects )
	_build_defeat_vignette()
	pass


#清空所有正在播放的临时特效（灰尘、打击粒子）
func clear_effects() -> void:
	for c in get_children():
		#暗角遮罩是常驻节点，不随特效清空销毁（它挂在自己的 CanvasLayer 下，只需重置透明度）
		if c == _defeat_vignette_layer:
			continue
		c.queue_free()
	#兜底：切场景时聚焦慢动作可能还在进行，把时间缩放与镜头聚焦一起复位，避免新关卡以 0.25 倍速开局。
	#令牌自增会让旧的演出协程在 await 之后自动作废
	_defeat_focus_token += 1
	_defeat_focus_active = false
	Engine.time_scale = 1.0
	if _defeat_vignette_tween:
		_defeat_vignette_tween.kill()
		_defeat_vignette_tween = null
	if _defeat_vignette:
		_defeat_vignette.modulate.a = 0.0
	_free_defeat_glow()
	camera_focus_released.emit()
	pass


func _create_dust_effect( pos : Vector2 ) -> DustEffect:
	var dust : DustEffect = DUST_EFFECT.instantiate()
	add_child( dust )
	dust.global_position = pos
	return dust


func jump_dust( pos : Vector2 ) -> void:
	var dust : DustEffect = _create_dust_effect( pos )
	dust.start( DustEffect.TYPE.JUMP )
	pass


func land_dust( pos : Vector2 ) -> void:
	var dust : DustEffect = _create_dust_effect( pos )
	dust.start( DustEffect.TYPE.LAND )
	pass


func hit_dust( pos : Vector2 ) -> void:
	var dust : DustEffect = _create_dust_effect( pos )
	dust.start( DustEffect.TYPE.HIT )
	pass


func hit_particles( pos: Vector2 , dir: Vector2 , settings : HitParticleSettings ) -> void:
	var p : HitParticles = HIT_PARTICLES.instantiate()
	add_child( p )
	p.global_position = pos
	p.start( dir , settings )
	pass


func camera_shake( strength : float = 1.0 , duration : float = 0.25 ) -> void:
	camera_shook.emit( strength , duration )
	pass


#演出（视频/过场）序列：镜头平滑推入并锁定到 world_pos（0.3~0.8 秒），
#zoom_level 为整数倍缩放（1 = 不缩放）。到达后保持，直到调用 camera_sequence_release。
func camera_sequence_to( world_pos : Vector2 , duration : float = 0.5 , zoom_level : float = 1.0 ) -> void:
	camera_sequence_started.emit( world_pos , duration , zoom_level )
	pass


#结束演出序列镜头：平滑回到玩家跟随（0.3~0.8 秒）
func camera_sequence_release( duration : float = 0.5 ) -> void:
	camera_sequence_released.emit( duration )
	pass


#region /// 击败 BOSS：聚焦 + 慢动作

#击败 BOSS 的聚焦演出：镜头锁定 + 全局慢动作 + 暗角/光晕，整段按真实秒数推进。
#world_pos 为聚焦点（传 BOSS 精灵中心，即它的视觉中心）；focus_node 传 BOSS 本体时，
#会在它身后加一圈焦点光晕（传 null 则只有暗角）。
#只触发一次：重复进入死亡状态或同帧多次调用都会被 _defeat_focus_active 挡住
func boss_defeat_focus( world_pos : Vector2 , focus_node : Node2D = null ) -> void:
	if _defeat_focus_active:
		return
	_defeat_focus_active = true
	_defeat_focus_token += 1
	var token : int = _defeat_focus_token

	#1) 镜头平滑推入并锁定到 BOSS 倒下的位置
	camera_focused.emit( world_pos , DEFEAT_FOCUS_CAM_IN , DEFEAT_FOCUS_CAM_OUT )
	#2) 全局慢动作：先落时间缩放，下面遮罩/光晕的补间才知道要按 0.25 倍速做反向补偿
	Engine.time_scale = DEFEAT_FOCUS_TIME_SCALE
	#3) BOSS 身后的焦点光晕（加色混合，只提亮不遮挡）+ 四周暗角淡入
	_spawn_defeat_glow( focus_node , world_pos )
	_fade_vignette( DEFEAT_VIGNETTE_ALPHA , DEFEAT_VIGNETTE_FADE_IN )

	#4) 真实 2 秒（ignore_time_scale = true：慢动作期间 delta 被缩放，普通计时器会被拉长 4 倍）
	await get_tree().create_timer( DEFEAT_FOCUS_HOLD , true , false , true ).timeout
	if token != _defeat_focus_token:
		return

	#5) 镜头回归与时间缩放恢复同时进行（镜头回归在 PlayerCamera 里同样按真实秒数走）
	camera_focus_released.emit()
	_fade_vignette( 0.0 , DEFEAT_FOCUS_CAM_OUT )
	_fade_defeat_glow( 0.0 , DEFEAT_FOCUS_CAM_OUT )
	await _restore_time_scale( token )
	_defeat_focus_active = false
	pass


#时间缩放从慢动作缓动回 1.0：慢动作期间 delta 与补间都被引擎缩放，所以这里用真实时钟
#（Time.get_ticks_msec）手动步进，并用 smoothstep 缓动，避免恢复末尾出现速度突变
func _restore_time_scale( token : int ) -> void:
	var from : float = Engine.time_scale
	var start_ms : int = Time.get_ticks_msec()
	var duration_ms : float = maxf( DEFEAT_FOCUS_RESTORE , 0.01 ) * 1000.0
	while true:
		#演出被切场景 / 新的击败接管：时间缩放交给接管方（clear_effects 或新的演出）处理
		if token != _defeat_focus_token:
			return
		var t : float = clampf( float( Time.get_ticks_msec() - start_ms ) / duration_ms , 0.0 , 1.0 )
		Engine.time_scale = lerpf( from , 1.0 , t * t * ( 3.0 - 2.0 * t ) )
		if t >= 1.0:
			break
		await get_tree().process_frame
	pass


#常驻暗角遮罩：独立 CanvasLayer（层 1，画在世界之上、玩家 HUD 之下），全屏径向渐变——
#中心一路透明、只有外围一圈渐黑。挂成常驻节点而不是临时特效，避免被 clear_effects 清掉
func _build_defeat_vignette() -> void:
	_defeat_vignette_layer = CanvasLayer.new()
	_defeat_vignette_layer.name = "DefeatFocusVignette"
	_defeat_vignette_layer.layer = 1
	add_child( _defeat_vignette_layer )

	var rect := TextureRect.new()
	rect.name = "Vignette"
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset( Control.PRESET_FULL_RECT )
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	#中心一大圈保持全透明：BOSS 聚焦后正好落在画面中央区域，不会被压暗
	rect.texture = _make_radial_texture( Color( 0.0 , 0.0 , 0.0 , 0.0 ) , Color( 0.0 , 0.0 , 0.0 , 1.0 ) , DEFEAT_VIGNETTE_INNER )
	rect.modulate.a = 0.0
	_defeat_vignette_layer.add_child( rect )
	_defeat_vignette = rect
	pass


#径向渐变贴图：fill_from 取贴图中心、fill_to 取右边缘 —— 渐变的 0 落在圆心、1 落在半径处。
#inner_keep 之前的半径保持 center_color，之后渐变到 edge_color
func _make_radial_texture( center_color : Color , edge_color : Color , inner_keep : float = 0.0 ) -> GradientTexture2D:
	var grad := Gradient.new()
	grad.set_color( 0 , center_color )
	grad.set_color( 1 , edge_color )
	if inner_keep > 0.0:
		grad.add_point( inner_keep , center_color )
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2( 0.5 , 0.5 )
	tex.fill_to = Vector2( 1.0 , 0.5 )
	tex.width = 64
	tex.height = 64
	return tex


#BOSS 身后的焦点光晕：挂在 BOSS 所在场景、插在它前一位并沿用它的层号（与 play_effect 的 under
#规则一致），所以关卡把 BOSS 的 z_index 改成几层都不会盖住它；加色混合的柔和径向亮光只提亮周边，
#不改 BOSS 精灵本身（8x7 图集做描边会在帧与帧之间串色）
func _spawn_defeat_glow( under : Node2D , world_pos : Vector2 ) -> void:
	if under == null or under.get_parent() == null:
		return
	var glow := Sprite2D.new()
	glow.name = "DefeatFocusGlow"
	glow.centered = true
	glow.texture = _make_radial_texture( Color( 1.0 , 1.0 , 1.0 , 1.0 ) , Color( 1.0 , 1.0 , 1.0 , 0.0 ) )
	#径向贴图 64x64、渐变半径 32px：按目标世界半径换算缩放
	glow.scale = Vector2.ONE * ( DEFEAT_GLOW_RADIUS / 32.0 )
	glow.modulate = Color( 1.0 , 0.7 , 0.85 , 0.0 )
	var blend := CanvasItemMaterial.new()
	blend.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = blend

	var world : Node = under.get_parent()
	world.add_child( glow )
	world.move_child( glow , under.get_index() )
	glow.z_index = under.z_index
	glow.global_position = world_pos
	_defeat_glow = glow
	_defeat_glow_tween = _tween_modulate_alpha( glow , DEFEAT_GLOW_ALPHA , DEFEAT_VIGNETTE_FADE_IN )
	pass


func _fade_vignette( alpha : float , time : float ) -> void:
	if _defeat_vignette == null:
		return
	if _defeat_vignette_tween:
		_defeat_vignette_tween.kill()
	_defeat_vignette_tween = _tween_modulate_alpha( _defeat_vignette , alpha , time )
	pass


func _fade_defeat_glow( alpha : float , time : float ) -> void:
	if _defeat_glow == null or not is_instance_valid( _defeat_glow ):
		return
	if _defeat_glow_tween:
		_defeat_glow_tween.kill()
	_defeat_glow_tween = _tween_modulate_alpha( _defeat_glow , alpha , time )
	#淡出结束再销毁光晕
	_defeat_glow_tween.tween_callback( _free_defeat_glow )
	pass


func _free_defeat_glow() -> void:
	_defeat_glow_tween = null
	if _defeat_glow != null and is_instance_valid( _defeat_glow ):
		_defeat_glow.queue_free()
	_defeat_glow = null
	pass


#遮罩 / 光晕的透明度补间：按当前 time_scale 反向补偿速度 —— 慢动作期间 delta 被引擎缩放，
#补偿后它们仍按真实秒数过渡（与 HUD 的"UI 不受慢动作影响"同一口径）
func _tween_modulate_alpha( canvas : CanvasItem , alpha : float , time : float ) -> Tween:
	var tw := canvas.create_tween()
	tw.set_speed_scale( 1.0 / maxf( Engine.time_scale , 0.001 ) )
	tw.tween_property( canvas , "modulate:a" , alpha , time ).set_trans( Tween.TRANS_SINE ).set_ease( Tween.EASE_IN_OUT )
	return tw

#endregion


#播放 BOSS 特效表的一段帧区间（first/last 为整表绝对帧号，如 FX_ROW_SPIKE ~ FX_ROW_SPIKE_END）。
#under 传入参照对象（如 BOSS 本体）：特效改挂在它所在的场景里、插在它的前一位，并沿用它的 z_index。
#这样不论该对象在关卡实例里被设成几层（BOSS 的 z_index 常被关卡覆盖），特效都稳定地画在
#「它之后、它之前的背景/地面之前」——既不会被不透明背景盖住，也不会挡住它
func play_effect( first_frame : int , last_frame : int , pos : Vector2 , scale_mult : float = 1.0 , flip : bool = false , fps : float = FX_DEFAULT_FPS , under : Node2D = null ) -> void:
	var fx := OneShotEffect.new()
	#特效配色：under 暴露出 current_tint() 时（传 BOSS 本体即是如此）用它的当前阶段配色，否则保持原色。
	#从 under 上取而非加参数：调用方只要传 BOSS 本体，特效颜色就自然跟着 BOSS 一起变化
	if under != null and under.has_method( "current_tint" ):
		var tint : Variant = under.call( "current_tint" )
		if tint is Color:
			fx.modulate = tint
	if under != null and under.get_parent() != null:
		var world : Node = under.get_parent()
		var idx : int = under.get_index()
		world.add_child( fx )
		#插在参照对象的前一位：同层同树序，画在它之下、它之前的所有节点（背景/地面）之上
		world.move_child( fx , idx )
		fx.z_index = under.z_index
	else:
		#没给参照对象时用默认特效层：抬高绘制层，否则会被关卡背景/前景盖住
		fx.z_index = FX_Z_INDEX
		add_child( fx )
	fx.global_position = pos
	fx.play( BOSS_EFFECTS , BOSS_EFFECTS_COLUMNS , BOSS_EFFECTS_ROWS , first_frame , last_frame , fps , scale_mult , flip )
	pass


#按特效表内的行号播放整行（row 为行索引，0 起）：0 尖刺爆发 / 1 像素爆散 / 2 垂直消散
#under 语义同 play_effect：传 BOSS 本体时特效自动跟随它的层级、贴它身后，并取它当前的阶段配色
func play_effect_row( row : int , pos : Vector2 , scale_mult : float = 1.0 , flip : bool = false , fps : float = FX_DEFAULT_FPS , under : Node2D = null ) -> void:
	var first : int = BOSS_EFFECTS_COLUMNS * clampi( row , 0 , BOSS_EFFECTS_ROWS - 1 )
	var last : int = first + BOSS_EFFECTS_COLUMNS - 1
	match row:
		0:
			last = FX_ROW_SPIKE_END
		1:
			last = FX_ROW_BURST_END
		2:
			last = FX_ROW_FADE_END
	play_effect( first , last , pos , scale_mult , flip , fps , under )
	pass


#在命中位置弹出伤害数字（amount 为负值时显示为回血 +N）
func spawn_damage_number( pos : Vector2 , amount : float , big : bool = false ) -> void:
	var dn := DamageNumber.new()
	add_child( dn )
	dn.global_position = pos
	dn.setup( amount , big )
	pass
