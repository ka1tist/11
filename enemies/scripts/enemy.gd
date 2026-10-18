@tool
@icon( "res://general/icons/enemy.svg" )
class_name Enemy extends CharacterBody2D


signal direction_changed( new_dir )
signal was_hit( a : AttackArea )
signal was_killed()

@export var health : float = 3.0
@export var affected_by_gravity : bool = true
@export var face_left_on_start : bool = false:
	set( value ):
		face_left_on_start = value
		_update_face_left()
#打开后每次攻击触发/未触发霸体都会在控制台打印状态与冷却剩余（调试用）
@export var debug_armor : bool = false


var sprite : Sprite2D
var animation : AnimationPlayer
var hazard_area : HazardArea
var damage_area : DamageArea

var state_machine : EnemyStateMachine
var decision_engine : DecisionEngine
var blackboard : Blackboard

#玩家死亡后冻结：true时停止一切物理/AI更新，仅保持死亡瞬间的画面
var frozen : bool = false

#攻击霸体：攻击起手时计数，每第 armor_every_n_attacks 次攻击起手的这一次获得霸体，
#持续整段攻击动作，期间免疫击退/眩晕等控制效果（伤害照常结算，死亡判定照旧）。
#计数以「攻击起手次数」为准：第一下攻击中途被打断（切进击退/眩晕）也照样算作一次，
#所以紧接着的第二下攻击依然会拿到霸体。内置 5 秒冷却：触发过一次后，5 秒内的攻击不再触发
#（每只小怪各自独立计时；墙钟计时，不受 Engine.time_scale 影响）
const ARMOR_COOLDOWN_MSEC : int = 5000
#每第几次攻击起手授予霸体：2 = 第一下不给（可被抢断）、第二下给、第三下不给、第四下给…
#改成 1 即每次攻击都授予霸体（按节奏调试用，关卡里可逐只小怪单独调）
@export_range( 1 , 8 , 1 ) var armor_every_n_attacks : int = 2
#已经起手过的攻击次数（含被打断的那些）：只增不减，不做重置，所以节奏不会被抢断打乱
var attack_count : int = 0
#霸体是否处于激活状态（调试标记：可直接在远程调试器里查看）
var armor_active : bool = false
#本次霸体结束的墙钟时刻（Time.get_ticks_msec）
var armor_end_msec : int = 0
#下一次攻击可以再次触发霸体的墙钟时刻
var armor_ready_msec : int = 0



func _ready() -> void:
	if Engine.is_editor_hint():
		set_physics_process( false )
		return
	setup()
	pass


func setup() -> void:
	blackboard = Blackboard.new()
	blackboard.health = health
	#玩家死亡广播：场景中每个存活敌人各自接收并立即冻结
	Messages.player_died.connect( freeze )
	
	for c in get_children():
		if c is AnimationPlayer and not animation:
			animation = c
		elif c is Sprite2D and not sprite:
			sprite = c
		elif c is DamageArea and not damage_area:
			damage_area = c
			c.damage_taken.connect( _on_damage_taken )
		elif c is HazardArea and not hazard_area:
			hazard_area = c
		elif c is EnemyStateMachine and not state_machine:
			state_machine = c
		elif c is DecisionEngine and not decision_engine:
			decision_engine = c
		pass
	
	if state_machine and decision_engine :
		state_machine.setup( self , blackboard )
		decision_engine.enemy = self
		decision_engine.blackboard = blackboard
	else:
		set_physics_process( false )
	pass


func _physics_process( delta: float ) -> void:
	if frozen:
		return
	#霸体到期即清掉激活标记：保持 armor_active 与实际生效状态一致，便于调试查看
	if armor_active and Time.get_ticks_msec() >= armor_end_msec:
		armor_active = false
	blackboard.update_distance_to_target( global_position )
	state_machine.change_state( decision_engine.decide() )
	if affected_by_gravity:
		velocity += get_gravity() * delta
	state_machine.physics_update( delta )
	move_and_slide()
	pass


#玩家死亡时调用：冻结移动/攻击/AI/动画，并关闭所有对玩家产生伤害的判定区。
#死亡后场景会随读档/回标题重建，本方法无需恢复
func freeze() -> void:
	if frozen:
		return
	frozen = true
	#停止物理帧：决策引擎、状态机（寻路/追击/攻击行为）、重力与move_and_slide全部停摆
	set_physics_process( false )
	velocity = Vector2.ZERO
	#暂停在当前动画帧（不能用stop()：Godot4的stop()会重置回第0帧）
	if animation:
		animation.pause()
	#关闭近战攻击判定区与接触伤害区（HazardArea也是AttackArea子类），
	#冻结后不再对玩家或其他对象产生任何伤害交互。
	#必须延迟设置属性：致命一击可能正来自该判定区的body_entered回调，
	#信号派发期间Area2D处于locked，直接改monitoring会被引擎阻止。
	#注意只能用属性名set_deferred：对GDScript自定义方法名（带默认参数的
	#set_activate）走消息队列调用在Godot4中不会生效
	for c in find_children( "*" ):
		if c is AttackArea:
			c.set_deferred( "monitoring" , false )
			c.set_deferred( "visible" , false )
	pass


func change_dir( new_dir : float ) -> void:
	blackboard.dir = new_dir
	direction_changed.emit( new_dir )
	if sprite:
		if new_dir < 0 :
			sprite.flip_h = true
		elif new_dir > 0 :
			sprite.flip_h = false
	pass



func play_animation( anim_name : String ) -> void:
	if animation.has_animation( anim_name ):
		animation.play( anim_name )
	else:
		printerr( "动画缺失:" , anim_name )
	pass


#region /// 攻击霸体

#攻击起手调用（各攻击状态 enter 里、播放攻击动画之后）：累计一次攻击起手，
#本次是第 armor_every_n_attacks 次且 5 秒冷却已过 → 授予霸体（覆盖整段攻击动作）。
#第一下不给霸体、可被玩家抢断（中断后切进击退/眩晕，本次攻击作废），
#但计数照加不误，所以紧接着的第二下攻击依然会拿到霸体。
#冷却只在真正授予时写入，冷却期内的攻击不会把冷却往后推（不存在重置异常）；
#霸体用「单个激活标记 + 到期时刻」表示，物理上不可能叠加，同一次攻击也不可能重复起手。
func start_attack_armor() -> void:
	var now : int = Time.get_ticks_msec()
	attack_count += 1
	var every : int = maxi( armor_every_n_attacks , 1 )
	if attack_count % every != 0:
		if debug_armor:
			print( "[霸体] %s 未触发：本次是第 %d 次攻击起手（每 %d 次授予）" % [ String( name ) , attack_count , every ] )
		return
	if now < armor_ready_msec:
		if debug_armor:
			print( "[霸体] %s 未触发：第 %d 次攻击起手，但冷却剩余 %.2fs" % [ String( name ) , attack_count , armor_cooldown_left() ] )
		return
	var action_time : float = _attack_action_time()
	armor_active = true
	armor_end_msec = now + int( action_time * 1000.0 )
	armor_ready_msec = now + ARMOR_COOLDOWN_MSEC
	if debug_armor:
		print( "[霸体] %s 触发：第 %d 次攻击起手，持续 %.2fs，冷却 %.2fs" % [ String( name ) , attack_count , action_time , float( ARMOR_COOLDOWN_MSEC ) / 1000.0 ] )
	pass


#霸体是否正在生效（激活中且未到期）：受击回调据此决定要不要把控制效果记进黑板
func is_armored() -> bool:
	return armor_active and Time.get_ticks_msec() < armor_end_msec


#冷却剩余秒数（调试用，0 表示下次攻击即可触发霸体）
func armor_cooldown_left() -> float:
	return maxf( float( armor_ready_msec - Time.get_ticks_msec() ) / 1000.0 , 0.0 )


#本次攻击动作的总时长：取当前动画的剩余播放长度（霸体覆盖整段攻击动作）
func _attack_action_time() -> float:
	if animation and animation.current_animation != "":
		return maxf( animation.current_animation_length - animation.current_animation_position , 0.0 )
	return 0.0

#endregion


func _on_damage_taken( a : AttackArea ) -> void:
	blackboard.health -= a.damege
	#霸体期间免疫控制效果：受击伤害照常结算，但不把受击来源记进黑板——
	#决策引擎正是靠黑板里的 damage_source 才会切进击退/眩晕状态，不记就等于打不断本次攻击。
	#两个例外必须照记：
	#1) 致命一击——决策引擎靠「damage_source 有值 + 血量<=0」这条分支切进死亡状态，不记就死不掉；
	#2) 普通受击——没有霸体时一切照旧。
	if blackboard.health <= 0 or not is_armored():
		blackboard.damage_source = a
	if blackboard.health <= 0 :
		damage_area.queue_free()
		hazard_area.queue_free()
		was_killed.emit()
	was_hit.emit( a )
	pass


func _get_configuration_warnings() -> PackedStringArray:
	var warnings : PackedStringArray = []
	
	if not find_children( "*" , "AnimationPlayer" , false ):
		warnings.append( "缺少AnimationPlayer" )
	if not find_children( "*" , "Sprite2D" , false ):
		warnings.append( "缺少Sprite2D" )
	if not find_children( "*" , "DamageArea" , false ):
		warnings.append( "缺少DamageArea" )
	if not find_children( "*" , "HazardArea" , false ):
		warnings.append( "缺少HazardArea" )
	if not find_children( "*" , "EnemyStateMachine" , false ):
		warnings.append( "缺少EnemyStateMachine" )
	if not find_children( "*" , "DecisionEngine" , false ):
		warnings.append( "缺少DecisionEngine" )
	
	return warnings



func _update_face_left() -> void:
	if not Engine.is_editor_hint():
		return
	for c in get_children():
		if c is Sprite2D:
			c.flip_h = face_left_on_start
	pass
