@tool
@icon( "res://general/icons/enemy.svg" )
class_name Enemy extends CharacterBody2D


signal direction_changed( new_dir )
signal was_hit( a : AttackArea )
signal was_killed()

@export var health : float = 3.0
@export var affected_by_gravity : bool = true
@export var face_left_on_start : bool = false


var sprite : Sprite2D
var animation : AnimationPlayer
var hazard_area : HazardArea
var damage_area : DamageArea

var state_machine : EnemyStateMachine
var decision_engine : DecisionEngine
var blackboard : Blackboard



func _ready() -> void:
	if Engine.is_editor_hint():
		set_physics_process( false )
		return
	setup()
	pass


func setup() -> void:
	blackboard = Blackboard.new()
	blackboard.health = health
	
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
	state_machine.change_state( decision_engine.decide() )
	if affected_by_gravity:
		velocity += get_gravity() * delta
	state_machine.physics_update( delta )
	move_and_slide()
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
