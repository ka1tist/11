class_name PlayerStateAttack extends PlayerState

@onready var sprite_2d: Sprite2D = $"../../Sprite2D"
@onready var sprite_2d_2: Sprite2D = $"../../Sprite2D2"


const AUDIO_ATTACK = preload("uid://45r5bi2yyufq")

@export var combo_time_window : float = 0.2
@export var speed : float = 200
const COMBO_ANIMATIONS : Array = ["attack", "attack_2"]
var timer : float = 0
var combo : int = 0


#状态初始化时做什么
func init() -> void:
	pass
	
	
#当我们进入这个状态时会发生什么
func enter() -> void:
	sprite_2d.visible = true
	sprite_2d_2.visible = false
	do_attack()
	player.animation_player.animation_finished.connect( _on_animation_finished )
	pass
	
#当我们退出这个状态会发生什么
func exit() -> void:
	sprite_2d.visible = false
	sprite_2d_2.visible = true
	timer = 0
	combo = 0
	player.animation_player.animation_finished.disconnect( _on_animation_finished )
	next_state = null
	pass

#按下输入会发生什么
func handle_input( _event : InputEvent ) -> PlayerState:
	#处理输入
	if  _event.is_action_pressed("attack"):
		timer = combo_time_window
	if _event.is_action_pressed( "dash" ) and player.can_dash():
		return dash
	return null
	
	
#在这个状态下，每个过程tick会发生什么
func process(delta: float) -> PlayerState:
	timer -= delta
	return next_state


#在这个状态下，每个物理过程tick会发生什么
func physics_process(_delta: float) -> PlayerState:
	player.velocity.x = player.direction.x * speed
	
	return null


func do_attack() -> void:
	player.animation_player.play( COMBO_ANIMATIONS[combo] )
	player.attack_area.activate()
	Audio.play_spatial_sound( AUDIO_ATTACK , player.global_position )
	pass


func _end_attack() -> void:
	if timer > 0:
		combo = wrapi( combo + 1 , 0 , 2 )
		do_attack()
	else:
		next_state = idle if player.is_on_floor() else fall
	pass


func _on_animation_finished( _anim_name : String ) -> void:
	_end_attack()
	pass
