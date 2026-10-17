class_name ESAttack extends EnemyState

@export var attack_range : float = 100.0
@export var move_speed : float = 200
@export var cooldown : float = 2.0
@export var attack_area : AttackArea
@export var move_speed_curve : Curve
@export var attack_animations : PackedStringArray = [ "attack", "attack_2" ]
@export var stationary_animations : PackedStringArray = [ "attack_2" ]

var timer : float = 0
var duration : float = 0
var on_cooldown : bool = false
var _stationary : bool = false



func enter() -> void:
	var picked_anim : String = _pick_attack_animation()
	_stationary = stationary_animations.has( picked_anim )
	enemy.play_animation( picked_anim )
	#攻击起手帧：按内置冷却尝试施加霸体（刷新到整段攻击动作；冷却中则本次攻击没有霸体）
	enemy.start_attack_armor()
	duration = enemy.animation.current_animation_length
	timer = 0
	blackboard.can_decide = false
	on_cooldown = true
	enemy.velocity.x = 0.0 if _stationary else move_speed * blackboard.dir
	if attack_area:
		attack_area.flip( blackboard.dir )
	pass


func re_enter() -> void:
	pass


func exit() -> void:
	blackboard.can_decide = true
	if enemy.sprite:
		enemy.sprite.modulate = Color.WHITE
	run_cooldown()
	pass


func physics_update( _delta: float ) -> void:
	timer += _delta
	if timer >= duration:
		blackboard.can_decide = true
	if _stationary:
		enemy.velocity.x = 0.0
	elif move_speed_curve:
		var sample : float = move_speed_curve.sample( timer / duration )
		enemy.velocity.x = move_speed * sample * blackboard.dir
	pass


func can_attack() -> bool:
	if blackboard.distance_to_target <= attack_range and not on_cooldown:
		return true
	return false


func _pick_attack_animation() -> String:
	var fallback : String = animation_name if animation_name else "attack"
	var available : PackedStringArray = PackedStringArray()
	for anim in attack_animations:
		if anim != "" and enemy.animation.has_animation( anim ):
			available.append( anim )
	if available.is_empty():
		return fallback
	return available[ randi() % available.size() ]



func run_cooldown() -> void:
	await  get_tree().create_timer( cooldown ).timeout
	on_cooldown = false
	pass
