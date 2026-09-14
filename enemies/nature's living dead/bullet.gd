class_name EnemyBullet
extends AttackArea

#飞行敌人远程子弹：继承 AttackArea 以复用伤害值(damege)、命中尘土特效与玩家 DamageArea 受伤链路。
#沿X轴匀速直线飞行，不受重力等物理效果影响（本节点是 Area2D，不参与物理刚体模拟）。
#碰到玩家 DamageArea → 造伤害并销毁；碰到世界实体(层1) → 销毁；超时兜底销毁。

@export var bullet_speed : float = 250.0
## 子弹存活时间（秒），超时自动销毁，防止未命中时无限飞行
@export var lifetime : float = 3.0

var _dir_x : float = 1.0
var _alive_time : float = 0.0


#发射初始化：飞行方向 / 伤害 / 速度，由攻击状态在生成子弹时调用
func setup( dir_x : float , dmg : float , spd : float ) -> void:
	_dir_x = 1.0 if is_zero_approx( dir_x ) else signf( dir_x )
	damege = dmg
	bullet_speed = spd
	var spr := get_node_or_null( "Sprite2D" ) as Sprite2D
	if spr:
		spr.flip_h = _dir_x < 0.0
	pass


func _ready() -> void:
	#不调用 super()：AttackArea._ready 会关闭 monitoring 并隐藏整个节点，
	#子弹需要常显且持续检测；此处只保留它的信号连接逻辑
	body_entered.connect( _on_hit )
	area_entered.connect( _on_hit )
	collision_layer = 0
	collision_mask = 1 | 16  #层1=世界实体(撞墙消失)，层16=玩家
	monitoring = true
	monitorable = false
	var ap := get_node_or_null( "AnimationPlayer" ) as AnimationPlayer
	if ap and ap.has_animation( "bullet" ):
		ap.play( "bullet" )
	pass


func _physics_process( delta : float ) -> void:
	#匀速直线：每帧只改 x，y 恒定，无重力、无惯性
	position.x += _dir_x * bullet_speed * delta
	_alive_time += delta
	if _alive_time >= lifetime:
		queue_free()
	pass


func _on_hit( body : Node2D ) -> void:
	if body is DamageArea:
		#走 AttackArea 原有命中流程：take_damage + 命中尘土特效
		super._on_body_entered( body )
		queue_free()
	else:
		#撞墙/地形等非伤害目标：直接销毁
		queue_free()
	pass
