@tool
@icon( "res://general/icons/breakable.svg" )
class_name Breakable extends Node2D

signal  destroyed


@export var hp : float = 3
@export var fixed_hit_count : bool = false

@export_category( "Particles" )
@export var emission_offset : Vector2 = Vector2.ZERO
@export var hit_particles : Array[ HitParticleSettings ]
@export var destroy_particles : Array[ HitParticleSettings ]

@export_category( "Audio" )
@export var hit_audio : AudioStream = preload("uid://dedlvms7fc0q2")
@export var destroy_audio : AudioStream = preload("uid://i7p3xk1bocdd")


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	for c in get_children():
		if c is DamageArea:
			c.damage_taken.connect( _on_damage_taken )
	pass


func _on_damage_taken( attack_area : AttackArea ) -> void:
	if fixed_hit_count:
		hp -= 1
	else:
		hp -= attack_area.damege 
	
	var pos : Vector2 = global_position + emission_offset
	var dir : Vector2 = Vector2( 1 , -1 )
	if attack_area.global_position.x > global_position.x:
		dir.x *= -1
		
	if hp > 0:
		Audio.play_spatial_sound( hit_audio , pos )
		for p in hit_particles:
			VisualEffects.hit_particles( pos , dir , p )
	else:
		Audio.play_spatial_sound( destroy_audio , pos )
		for p in destroy_particles:
			VisualEffects.hit_particles( pos , dir , p )
		clear_collision()
		var tween : Tween = create_tween()
		tween.tween_property( self , "modulate" , Color( modulate , 0 ) , 0.4 )
		await tween.finished
		queue_free()
		
	pass



func clear_collision() -> void:
	for c in get_children():
		if c is StaticBody2D:
			c.queue_free()
	pass



func _get_configuration_warnings() -> PackedStringArray:
	if _check_for_damage_area() == false:
		return[ "缺少damagearea模块" ]
	else:
		return[]



func _check_for_damage_area() -> bool:
	for c in get_children():
		if c is DamageArea:
			return true
	return false
