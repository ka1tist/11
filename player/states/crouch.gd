class_name PlayerStateCrouch extends PlayerState

@onready var sprite_2d: Sprite2D = $"../../Sprite2D"
@onready var sprite_2d_2: Sprite2D = $"../../Sprite2D2"

@export var deceleration_rate : float = 20

#状态初始化时做什么
func init() -> void:
	pass
	
	
#进入这个状态时会发生什么
func enter() -> void:
	#动画
	sprite_2d.visible = true
	sprite_2d_2.visible = false
	player.animation_player.play( "crouch" )
	player.collision_stand.disabled = true
	player.collision_crouch.disabled = false
	player.da_stand.disabled = true
	player.da_crouch.disabled = false
	pass
	
#退出这个状态会发生什么
func exit() -> void:
	sprite_2d.visible = false
	sprite_2d_2.visible = true
	player.collision_stand.disabled = false
	player.collision_crouch.disabled = true
	player.da_stand.disabled = false
	player.da_crouch.disabled = true
	pass

#按下输入会发生什么
func handle_input( _event : InputEvent ) -> PlayerState:
	#处理输入
	if _event.is_action_pressed("attack"):
		return attack
	if _event.is_action_pressed("jump"):
		player.one_way_platform_shape_cast.force_shapecast_update()
		if player.one_way_platform_shape_cast.is_colliding() == true:
			player.position.y += 4
			return fall
		return jump
	return next_state
	
	
#在这个状态下，每个过程tick会发生什么
func process(_delta: float) -> PlayerState:
	if player.direction.y <= 0.5:
		return idle 
	return next_state


#在这个状态下，每个物理过程tick会发生什么
func physics_process(_delta: float) -> PlayerState:
	player.velocity.x -= player.velocity.x * deceleration_rate * _delta
	if player.is_on_floor() == false:
		return fall	
	return next_state
