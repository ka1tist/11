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


var sprite : Sprite2D
var animation : AnimationPlayer
var hazard_area : HazardArea
var damage_area : DamageArea

var state_machine : EnemyStateMachine
var decision_engine : DecisionEngine
var blackboard : Blackboard

#玩家死亡后冻结：true时停止一切物理/AI更新，仅保持死亡瞬间的画面
var frozen : bool = false



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


func _on_damage_taken( a : AttackArea ) -> void:
	blackboard.damage_source = a
	blackboard.health -= a.damege
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
