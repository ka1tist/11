class_name PlayerStateDash extends PlayerState

@onready var sprite_2d: Sprite2D = $"../../Sprite2D"
@onready var sprite_2d_2: Sprite2D = $"../../Sprite2D2"
@onready var sprite_2d_3: Sprite2D = $"../../Sprite2D3"
@onready var sprite_2d_4: Sprite2D = $"../../Sprite2D4"
@onready var damage_area: DamageArea = %DamageArea


const DASH_AUDIO = preload("uid://buwlsqoluvb8l")

@export var duration : float = 0.25
@export var speed : float = 300.0
@export var effect_delay : float = 0.05

var dir : float = 1.0
var time : float = 0.0
var effect_time : float = 0.0

#状态初始化时做什么
func init() -> void:
	pass
	
	
#当我们进入这个状态时会发生什么
func enter() -> void:
	sprite_2d.visible = false
	sprite_2d_2.visible = false
	sprite_2d_3.visible = false
	sprite_2d_4.visible = true
	get_dash_direction()
	sprite_2d_4.flip_h = dir < 0
	sprite_2d_4.position.x = -21.0 if dir > 0 else 21.0
	player.animation_player.play( "dash" )
	time = duration
	effect_time = 0.0
	damage_area.make_invulnerable( duration )
	Audio.play_spatial_sound( DASH_AUDIO , player.global_position , false , true , 0.75 )
	player.gravity_mulitplier = 0.0
	player.velocity.y = 0
	
	player.dash_count += 1
	#地面dash时记录时间戳并进入冷却，供can_dash()判定与就绪粒子提示
	if player.is_on_floor():
		player.last_ground_dash_msec = Time.get_ticks_msec()
	pass
	
#当我们退出这个状态会发生什么
func exit() -> void:
	sprite_2d.visible = true
	sprite_2d_4.visible = false
	player.gravity_mulitplier = 1.0
	pass

#按下输入会发生什么
func handle_input( _event : InputEvent ) -> PlayerState:

	return null
	
	
#在这个状态下，每个过程tick会发生什么
func process(_delta: float) -> PlayerState:
	time -= _delta
	if time <= 0:
		if player.is_on_floor():
			return idle
		else:
			return fall
	
	effect_time -= _delta
	if effect_time < 0:
		effect_time = effect_delay
		player.sprite_2d_4.ghost()
	return null


#在这个状态下，每个物理过程tick会发生什么
func physics_process(_delta: float) -> PlayerState:
	player.velocity.x = ( speed * ( time / duration ) + speed ) * dir
	return next_state



func get_dash_direction() -> void:
	dir = 1.0
	if player.sprite.flip_h == true:
		dir = -1
	pass
