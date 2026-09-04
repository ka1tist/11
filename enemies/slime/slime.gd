@icon( "res://general/icons/enemy.svg" )
class_name Slime extends CharacterBody2D


@export var health : float = 3
@export var move_speed : float = 30
@export var face_left_on_start : bool = false
@export var death_sound : AudioStream

var dir : float = 1.0
var move_tween : Tween

@onready var sprite_2d: Sprite2D = $Sprite2D
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var hazard_area: HazardArea = $HazardArea
@onready var damage_area: DamageArea = $DamageArea
@onready var edge_detector: EdgeDetector = $EdgeDetector


func _ready() -> void:
	animation_player.play( "walk" )
	animation_player.animation_finished.connect( _on_animation_finished )
	edge_detector.edge_detected.connect( _on_edge_detected )
	change_direction( -1.0 if face_left_on_start else 1.0 )
	damage_area.damage_taken.connect( _on_damage_taken )
	pass 



func _physics_process(delta: float) -> void:
	if is_on_wall():
		change_direction( -dir )
	velocity += get_gravity() * delta
	velocity.x = dir * move_speed
	move_and_slide()
	pass



func change_direction( new_dir : float ) -> void:
	dir = new_dir
	edge_detector.direction_changed( dir )
	if dir < 0 :
		sprite_2d.flip_h = true
	elif dir > 0 :
		sprite_2d.flip_h = false
	pass



func _on_edge_detected() -> void:
	if is_on_floor():
		change_direction( -dir )
	pass


func _on_damage_taken( attack_area : AttackArea ) -> void:
	health -= attack_area.damege
	
	
	knockback( attack_area.global_position )
	
	if health > 0 :
		#连续受击时强制从头播放stun：play()在stun已在播放时不会回到第0帧，需seek回起点重新播放
		animation_player.play( "stun" )
		animation_player.seek( 0.0 , true )
	else:
		animation_player.play( "death" )
		Audio.play_spatial_sound( death_sound , global_position )
		damage_area.queue_free()
		hazard_area.queue_free()
	pass

func knockback( a_pos : Vector2 ) -> void:
	var from : float = dir
	var to : float = dir
	if a_pos.x < global_position.x:
		from += 1
	else:
		from -= 1
	
	if move_tween:
		move_tween.kill()
	
	dir = from
	
	if health <= 0:
		to = 0
		
	move_tween = create_tween()
	move_tween.tween_property( self , "dir" , to , 0.3 )
	pass




func _on_animation_finished( anim_name : String ) -> void:
	if anim_name == "stun" :
		animation_player.play( "walk" )
	else:
		queue_free()
	pass
