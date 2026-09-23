class_name ESRangedAttack extends ESAttack



## 近程攻击距离（像素）：小于等于此距离用近程攻击，否则用远程攻击
@export var melee_range : float = 50.0
## 子弹场景（默认 nature's living dead 的 bullet）
@export var bullet_scene : PackedScene = preload( "res://enemies/nature's living dead/bullet.tscn" )
## 子弹飞行速度（像素/秒），匀速直线
@export var bullet_speed : float = 250.0
## 子弹伤害值
@export var bullet_damage : float = 1.0
## attack_2 动画中发射子弹的时间点（秒）
@export var bullet_fire_time : float = 0.5
## 子弹生成位置（敌人局部坐标）
@export var bullet_spawn_offset : Vector2 = Vector2( 0 , -24 )
## 远程攻击动画名
@export var ranged_animation : String = "attack_2"

var _is_ranged : bool = false
var _bullet_fired : bool = false


func enter() -> void:
	#目标在近程距离外且已被发现 → 远程；否则近程
	_is_ranged = blackboard.target != null and blackboard.distance_to_target > melee_range
	var picked_anim : String
	if _is_ranged:
		picked_anim = ranged_animation if ranged_animation else "attack_2"
		#远程攻击前转身面向玩家，保证动画朝向与子弹方向一致
		var dir_x : float = signf( blackboard.target.global_position.x - enemy.global_position.x )
		if is_zero_approx( dir_x ) == false:
			enemy.change_dir( dir_x )
	else:
		picked_anim = _pick_attack_animation()
	_stationary = true  #两种攻击都原地播放
	enemy.play_animation( picked_anim )
	duration = enemy.animation.current_animation_length
	timer = 0
	_bullet_fired = false
	blackboard.can_decide = false
	on_cooldown = true
	enemy.velocity.x = 0.0
	if attack_area and not _is_ranged:
		attack_area.flip( blackboard.dir )
	pass


func physics_update( delta : float ) -> void:
	timer += delta
	if timer >= duration:
		blackboard.can_decide = true
	if _is_ranged:
		#远程攻击原地不动
		enemy.velocity.x = 0.0
		#以 AnimationPlayer 的实际播放进度判定发射时机，与动画帧精确同步（仅发射一次）
		if _bullet_fired == false and enemy.animation.current_animation_position >= bullet_fire_time:
			_bullet_fired = true
			_fire_bullet()
	else:
		#近程攻击沿用父类位移曲线逻辑
		if _stationary == false and move_speed_curve:
			var sample : float = move_speed_curve.sample( timer / duration )
			enemy.velocity.x = move_speed * sample * blackboard.dir
	pass


#只要发现玩家且攻击冷却结束即可攻击：进入后按当前距离选择近程/远程模式
func can_attack() -> bool:
	return blackboard.target != null and not on_cooldown


func _fire_bullet() -> void:
	if bullet_scene == null:
		push_warning( "ESRangedAttack: bullet_scene 未配置，无法发射子弹" )
		return
	#发射瞬间再次确认目标仍在
	if blackboard.target == null:
		return
	var bullet := bullet_scene.instantiate()
	#挂到敌人父节点（关卡）下而非敌人体内：敌人死亡/缩放翻转不影响已射出的子弹
	var host : Node = enemy.get_parent() if is_instance_valid( enemy.get_parent() ) else get_tree().current_scene
	host.add_child( bullet )
	bullet.global_position = enemy.to_global( bullet_spawn_offset )
	var dir_x : float = signf( blackboard.target.global_position.x - enemy.global_position.x )
	if is_zero_approx( dir_x ):
		dir_x = blackboard.dir
	bullet.setup( dir_x , bullet_damage , bullet_speed )
	pass
