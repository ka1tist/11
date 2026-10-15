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


func _ready() -> void:
	#切换地图时清空残留特效：灰尘/粒子挂在autoload节点上会跨场景存活，
	#暂停期间被冻结、新地图淡入后继续播完，导致上一个地图的特效出现在新地图
	SceneManager.load_scene_started.connect( clear_effects )
	pass


#清空所有正在播放的临时特效（灰尘、打击粒子）
func clear_effects() -> void:
	for c in get_children():
		c.queue_free()
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


#播放 BOSS 特效表的一段帧区间（first/last 为整表绝对帧号，如 FX_ROW_SPIKE ~ FX_ROW_SPIKE_END）。
#under 传入参照对象（如 BOSS 本体）：特效改挂在它所在的场景里、插在它的前一位，并沿用它的 z_index。
#这样不论该对象在关卡实例里被设成几层（BOSS 的 z_index 常被关卡覆盖），特效都稳定地画在
#「它之后、它之前的背景/地面之前」——既不会被不透明背景盖住，也不会挡住它
func play_effect( first_frame : int , last_frame : int , pos : Vector2 , scale_mult : float = 1.0 , flip : bool = false , fps : float = FX_DEFAULT_FPS , under : Node2D = null ) -> void:
	var fx := OneShotEffect.new()
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
#under 语义同 play_effect：传 BOSS 本体时特效自动跟随它的层级、贴它身后
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
