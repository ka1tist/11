extends Node

const DUST_EFFECT = preload("uid://qs2i4ldiy3hl")
const HIT_PARTICLES = preload("uid://w5vvcvi053qg")

#BOSS 特效表：640x384 = 5列x3行，单帧 128x128
const BOSS_EFFECTS = preload("res://bosses/01/sprites/pink_box_effects.png")
const BOSS_EFFECTS_COLUMNS : int = 5
const BOSS_EFFECTS_ROWS : int = 3
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


#播放 BOSS 特效表的一段帧区间（first/last 为整表绝对帧号，如 FX_ROW_SPIKE ~ FX_ROW_SPIKE_END）
func play_effect( first_frame : int , last_frame : int , pos : Vector2 , scale_mult : float = 1.0 , flip : bool = false , fps : float = FX_DEFAULT_FPS ) -> void:
	var fx := OneShotEffect.new()
	add_child( fx )
	fx.global_position = pos
	fx.play( BOSS_EFFECTS , BOSS_EFFECTS_COLUMNS , BOSS_EFFECTS_ROWS , first_frame , last_frame , fps , scale_mult , flip )
	pass


#按特效表内的行号播放整行（row 为行索引，0 起）：0 尖刺爆发 / 1 像素爆散 / 2 垂直消散
func play_effect_row( row : int , pos : Vector2 , scale_mult : float = 1.0 , flip : bool = false , fps : float = FX_DEFAULT_FPS ) -> void:
	var first : int = BOSS_EFFECTS_COLUMNS * clampi( row , 0 , BOSS_EFFECTS_ROWS - 1 )
	var last : int = first + BOSS_EFFECTS_COLUMNS - 1
	match row:
		0:
			last = FX_ROW_SPIKE_END
		1:
			last = FX_ROW_BURST_END
		2:
			last = FX_ROW_FADE_END
	play_effect( first , last , pos , scale_mult , flip , fps )
	pass


#在命中位置弹出伤害数字（amount 为负值时显示为回血 +N）
func spawn_damage_number( pos : Vector2 , amount : float , big : bool = false ) -> void:
	var dn := DamageNumber.new()
	add_child( dn )
	dn.global_position = pos
	dn.setup( amount , big )
	pass
