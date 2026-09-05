class_name PlayerStateTakeDamage extends PlayerState

@onready var sprite_2d: Sprite2D = $"../../Sprite2D"
@onready var sprite_2d_2: Sprite2D = $"../../Sprite2D2"



@export var move_speed : float = 100
@export var invulnerable_duration : float = 0.5
var time : float = 0.0
var dir : float = 1.0 

@onready var damage_area: DamageArea = %DamageArea
@onready var hurt_audio: AudioStreamPlayer2D = %HurtAudio



#状态初始化时做什么
func init() -> void:
	damage_area.damage_taken.connect( _on_damage_taken )
	pass
	
	
#当我们进入这个状态时会发生什么
func enter() -> void:
	#动画
	sprite_2d.visible = true
	sprite_2d_2.visible = false
	player.animation_player.play( "take_damage" )
	time = player.animation_player.current_animation_length
	damage_area.make_invulnerable( invulnerable_duration )
	hurt_audio.play()
	VisualEffects.camera_shake( 5.0 , 0.25 )
	pass
	
#当我们退出这个状态会发生什么
func exit() -> void:
	pass

#按下输入会发生什么
func handle_input( _event : InputEvent ) -> PlayerState:
	return null
	
	
#在这个状态下，每个过程tick会发生什么
func process(_delta: float) -> PlayerState:
	time -= _delta
	if time <= 0:
		if player.hp <= 0 :
			return death
		return idle
	return null


#在这个状态下，每个物理过程tick会发生什么
func physics_process(_delta: float) -> PlayerState:
	player.velocity.x = move_speed * dir
	return null


func _on_damage_taken( attack_area : AttackArea ) -> void:
	if player.current_state == death:
		return
	player.change_state( self )
	if attack_area.global_position.x < player.global_position.x:
		dir = 1.0
	else:
		dir = -1.0
	pass
