extends Node

const DUST_EFFECT = preload("uid://qs2i4ldiy3hl")
const HIT_PARTICLES = preload("uid://w5vvcvi053qg")


signal camera_shook( strength : float )


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


func camera_shake( strength : float = 1.0 ) -> void:
	camera_shook.emit( strength )
	pass
