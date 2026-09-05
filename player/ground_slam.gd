class_name PlayerStateGroundSlam extends PlayerState

@onready var sprite_2d: Sprite2D = $"../../Sprite2D"
@onready var sprite_2d_2: Sprite2D = $"../../Sprite2D2"

@export var velocity : float = 400
@export var effect_delay : float = 0.075 
var effect_timer : float = 0

const DASH_AUDIO = preload("uid://buwlsqoluvb8l")
const BOOM_AUDIO = preload("uid://cw27cc6r81wl1")
const BREAK_WOOD_AUDIO = preload("uid://i7p3xk1bocdd")
const 地面破坏1 = preload("uid://dvt4krls7xq3u")
const 地面破坏2 = preload("uid://cceykp5dmd05y")
const 地面破坏3 = preload("uid://ot25twm6tx4o")

@onready var damage_area: DamageArea = %DamageArea
@onready var ground_slam_shape_cast: ShapeCast2D = $"../../GroundSlamShapeCast"
@onready var ground_slam_attack_area: AttackArea = %GroundSlamAttackArea





#状态初始化时做什么
func init() -> void:
	pass
	
	
#当我们进入这个状态时会发生什么
func enter() -> void:
	#动画
	sprite_2d.visible = true
	sprite_2d_2.visible = false
	player.animation_player.play( "ground_slam" )
	player.sprite.tween_color()
	Audio.play_spatial_sound( DASH_AUDIO , player.global_position )
	damage_area.start_invulnerable()
	ground_slam_attack_area.flip( -1 if player.sprite.flip_h else 1 )
	ground_slam_attack_area.set_activate()
	pass
	
#当我们退出这个状态会发生什么
func exit() -> void:
	VisualEffects.camera_shake( 8.0 , 0.4 )
	VisualEffects.land_dust( player.global_position )
	VisualEffects.hit_dust( player.global_position )
	Audio.play_spatial_sound( BOOM_AUDIO , player.global_position )
	damage_area.end_invulnerable()
	ground_slam_attack_area.set_activate( false )
	pass

#按下输入会发生什么
func handle_input( _event : InputEvent ) -> PlayerState:
	#处理输入
	return null
	
	
#在这个状态下，每个过程tick会发生什么
func process(_delta: float) -> PlayerState:
	check_collisions( _delta )
	effect_timer -= _delta
	if effect_timer < 0:
		effect_timer = effect_delay
		player.sprite.ghost()
	return null


#在这个状态下，每个物理过程tick会发生什么
func physics_process(_delta: float) -> PlayerState:
	player.velocity = Vector2( 0 , velocity )
	if player.is_on_floor():
		if not check_collisions( _delta ):
			return idle
	return next_state



func check_collisions( _delta ) -> bool:
	ground_slam_shape_cast.target_position.y = velocity * _delta
	ground_slam_shape_cast.force_shapecast_update()
	if ground_slam_shape_cast.is_colliding():
		for i in ground_slam_shape_cast.get_collision_count():
			var c = ground_slam_shape_cast.get_collider( i )
			var pos : Vector2 = ground_slam_shape_cast.get_collision_point( i )
			
			VisualEffects.hit_dust( pos )
			VisualEffects.camera_shake( 8.0 , 0.3 )
			
			if c.get_parent() is Breakable:
				var b : Breakable = c.get_parent()
				#destroy()内走完整击破流程（destroyed信号/音效/粒子/淡出），AbilityPickup等依赖destroyed信号
				b.destroy( Vector2.DOWN )
			else:
				if c is SlamBreakable:
					#SlamBreakable走destroy()记录持久化，切换地图后不再刷新
					c.destroy()
				else:
					c.queue_free()
				VisualEffects.hit_particles( pos , Vector2.UP , 地面破坏1 )
				VisualEffects.hit_particles( pos , Vector2.DOWN , 地面破坏2 )
				VisualEffects.hit_particles( pos , Vector2.UP , 地面破坏3 )
				Audio.play_spatial_sound( BREAK_WOOD_AUDIO , pos )
		return true
	return false