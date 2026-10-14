class_name PbProjectile extends Node2D

## 二/三阶段专属技能的投射物：沿发射方向水平直线飞行，命中玩家或撞到墙壁时播放 destroy 动画并销毁。
## 方向与速度由生成方（bosses/scripts/boss.gd 的 spawn_pb()）用 setup() 设置，
## 发射瞬间由生成方调用 AnimationPlayer 播放 default 动画。

#墙壁所在碰撞层（竞技场的地面/左右墙/天花板同为第 1 层）
@export var wall_mask : int = 1

#命中玩家时喷出的扇形粒子（散射角 90°，方向与投射物飞行方向一致）
const HIT_SETTINGS : HitParticleSettings = preload( "res://00_global/visual_effects/hit_particle_settings/pb击中.tres" )

var dir : Vector2 = Vector2.RIGHT
var speed : float = 350.0
#已进入销毁流程：防止玩家与墙壁在同一帧内命中时重复销毁
var _exploding : bool = false
var animation_player : AnimationPlayer
var hazard_area : HazardArea


func _ready() -> void:
	animation_player = get_node_or_null( "AnimationPlayer" ) as AnimationPlayer
	hazard_area = get_node_or_null( "HazardArea" ) as HazardArea
	if hazard_area:
		#判定区已被生成方改为只命中玩家层（16）；命中与否再由 _on_hit() 按受击判定区过滤
		hazard_area.body_entered.connect( _on_hit )
		hazard_area.area_entered.connect( _on_hit )
	pass


func setup( direction : Vector2 , move_speed : float ) -> void:
	dir = direction.normalized()
	speed = move_speed
	pass


func _physics_process( delta : float ) -> void:
	if _exploding:
		return

	#沿方向推进；先用射线预判本帧落点，命中墙壁即进入销毁，避免穿墙
	var to : Vector2 = global_position + dir * speed * delta
	var query := PhysicsRayQueryParameters2D.create( global_position , to , wall_mask )
	var hit : Dictionary = get_world_2d().direct_space_state.intersect_ray( query )
	if hit.is_empty():
		global_position = to
	else:
		_explode()
	pass


#命中玩家：只有真正进入玩家的受击判定区（DamageArea）才算数。
#玩家根节点（CharacterBody2D）与受击判定区同在 16 层，两者都会触发这里的进入回调，
#但伤害只由受击判定区结算（AttackArea 的进入回调会被受击判定区禁用挡掉）：
#玩家处于受击硬直/闪避/下落攻击的无敌期间时，其受击判定区被禁用，只剩根节点能被探到，
#若在那时判定为命中，就会出现"碰到玩家却没打中、投射物却自己炸掉"的假命中
func _on_hit( hit : Node2D ) -> void:
	if _exploding:
		return
	if not ( hit is DamageArea ):
		return
	#在命中位置沿投射物飞行方向喷出一片扇形粒子
	VisualEffects.hit_particles( global_position , dir , HIT_SETTINGS )
	_explode()


#命中玩家或墙壁：立刻停掉推进与判定，播放 destroy 动画，动画播完（或素材缺失）后销毁
func _explode() -> void:
	if _exploding:
		return
	_exploding = true
	set_physics_process( false )
	#销毁动画期间不再造成伤害；信号派发期间 Area2D 的 monitoring 被锁，必须延迟设置
	if hazard_area:
		hazard_area.set_deferred( "monitoring" , false )

	if animation_player and animation_player.has_animation( "destroy" ):
		animation_player.play( "destroy" )
		await get_tree().create_timer( animation_player.get_animation( "destroy" ).length ).timeout
	queue_free()
	pass
