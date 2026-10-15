@icon( "res://general/icons/enemy_hit_particles.svg" )
class_name EnemtHitParticles extends Marker2D

@export var hit_particles : Array[ HitParticleSettings ]
@export var death_particles : Array[ HitParticleSettings ]


var enemy_was_killed : bool = false

#最近一次受击的方向（BOSS 的死亡粒子复用它）
var _last_hit_dir : Vector2 = Vector2.RIGHT


func _ready() -> void:
	var target : Node = owner
	if target is Enemy:
		target.was_hit.connect( _on_hit )
		target.was_killed.connect( _on_killed )
	elif target is Boss:
		#BOSS 与小怪同构（同样广播 was_killed），但它没有 was_hit 信号：受击粒子照旧走 DamageArea.damage_taken。
		#死亡粒子必须在这里放：击杀那一刀里本节点的受击回调（子节点 _ready 期先注册，早于 BOSS 自己的受击回调）
		#会先执行，此时 was_killed 还没广播；等广播回来 BOSS 已经死了，不会再有下一次命中
		target.was_killed.connect( _on_boss_killed )
		_connect_damage_area()
	else:
		_connect_damage_area()
	pass


#没有 was_hit 信号的对象（BOSS 等）：受击判定挂在同一级的 DamageArea 上
func _connect_damage_area() -> void:
	for c in get_parent().get_children():
		if c is DamageArea:
			c.damage_taken.connect( _on_hit )
	pass


func _on_hit( a : AttackArea ) -> void:
	_last_hit_dir = global_position.direction_to( a.global_position )
	_last_hit_dir.x *= -1.0
	var settings : Array[ HitParticleSettings ] = hit_particles
	if enemy_was_killed:
		settings = death_particles
	_burst( settings , _last_hit_dir )
	pass


#小怪：击败广播早于自己发出的 was_hit，这里先置位，随后 _on_hit 就会改用死亡粒子
func _on_killed() -> void:
	enemy_was_killed = true
	pass


#BOSS 被击败：用击杀那一刀算出的方向，在死亡瞬间直接把死亡粒子放掉
func _on_boss_killed() -> void:
	enemy_was_killed = true
	_burst( death_particles , _last_hit_dir )
	pass


#逐条播放粒子配置；数组里可能留着没填的空槽（编辑器里清空过的元素是 null），跳过避免取属性报错
func _burst( settings : Array[ HitParticleSettings ] , dir : Vector2 ) -> void:
	for p in settings:
		if p == null:
			continue
		VisualEffects.hit_particles( global_position , dir , p )
	pass
