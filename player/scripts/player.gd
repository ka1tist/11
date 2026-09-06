class_name Player extends CharacterBody2D

const DEBUG_JUMP_INDICATOR = preload("uid://c20ut5uhd7s7g")
const MORPH = preload("uid://bw4a85fy11igm")
signal damage_taken

#region /// on ready variables
@onready var sprite: PlayerSprite = $Sprite2D
@onready var sprite_2d_2: Sprite2D = $Sprite2D2
@onready var sprite_2d_3: Sprite2D = $Sprite2D3
@onready var sprite_2d_4: PlayerSprite = $Sprite2D4
@onready var collision_stand: CollisionShape2D = $CollisionStand
@onready var collision_crouch: CollisionShape2D = $CollisionCrouch
@onready var da_stand: CollisionShape2D = %DAStand
@onready var da_crouch: CollisionShape2D = %DACrouch
@onready var one_way_platform_shape_cast: ShapeCast2D = $OneWayPlatformShapeCast
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var attack_area: AttackArea = %AttackArea
@onready var damage_area: DamageArea = %DamageArea
#记录各精灵的初始modulate，ready闪光结束后恢复为默认值而非运行时值
@onready var _sprite_default_modulates : Array[Color] = [
	sprite.modulate ,
	sprite_2d_2.modulate ,
	sprite_2d_3.modulate ,
	sprite_2d_4.modulate ,
]
#endregion

#region /// on ready variables
var hp : float = 20 : 
	set( value ) :
		hp = clampf( value , 0 , max_hp )
		Messages.player_health_changed.emit( hp , max_hp )

var max_hp : float = 20 : 
	set( value ) :
		max_hp = value
		Messages.player_health_changed.emit( hp , max_hp )

var dash : bool = false
var dash_count : int = 0
#地面dash内置CD：上次地面dash的时间戳（毫秒），防止在地面连续闪避
const GROUND_DASH_COOLDOWN_MSEC : int = 1000
var last_ground_dash_msec : int = -1000
#地面dash冷却是否进行中，用于在冷却结束时触发一次ready提示
var _ground_dash_cooldown_active : bool = false
var double_jump : bool = false
var jump_count : int = 0
var ground_slam : bool = false
var morph_roll : bool = false
#endregion

#region /// export variables
@export var move_speed : float = 200
@export var max_fall_velocity : float = 600
#endregion

#region /// state references
var states:Array[PlayerState]
var current_state : PlayerState :
	get: return states.front()
var previous_state : PlayerState :
	get: return states[ 1 ]
#endregion


#region /// standard references
var direction : Vector2 = Vector2.ZERO
var gravity : float = 980
var gravity_mulitplier : float = 1.0
#endregion


func _ready() -> void:
	#初始化状态
	if get_tree().get_first_node_in_group("Player") != self:
		self.queue_free()
	initialize_states()
	self.call_deferred( "reparent",get_tree().root )
	Messages.player_healed.connect( _on_player_healed )
	Messages.back_to_title_screen.connect( queue_free )
	damage_area.damage_taken.connect( _on_damage_taken )
	hp = max_hp
	pass

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_released("jump"):
		velocity.y *= 0.5
	if event.is_action_pressed( "action" ):
		Messages.player_interacted.emit( self )
	elif event.is_action_pressed( "pause" ):
		get_tree().paused = true
		var pause_menu : PauseMenu = load( "res://pause_menu/pause_menu.tscn" ).instantiate()
		add_child( pause_menu )
		return
	change_state( current_state.handle_input( event ) )
	pass


func _process(_delta: float) -> void:
	update_direction()
	_update_dash_ready()
	change_state( current_state.process( _delta ) )
	pass

#检测地面dash冷却是否转好，转好时播放一次ready闪光提示
func _update_dash_ready() -> void:
	if dash == false:
		return
	var elapsed : int = Time.get_ticks_msec() - last_ground_dash_msec
	if _ground_dash_cooldown_active == false:
		if elapsed < GROUND_DASH_COOLDOWN_MSEC:
			_ground_dash_cooldown_active = true
	else:
		if elapsed >= GROUND_DASH_COOLDOWN_MSEC:
			_ground_dash_cooldown_active = false
			Audio.play_spatial_sound( MORPH , global_position , -4.0 )
			_play_dash_ready_flash()
	pass


#ready闪光：用Tween短暂提亮当前可见的精灵后回到默认modulate，不干扰AnimationPlayer正在播放的状态动画
func _play_dash_ready_flash() -> void:
	var sprites : Array[Sprite2D] = [ sprite , sprite_2d_2 , sprite_2d_3 , sprite_2d_4 ]
	for i in range( sprites.size() ):
		var s : Sprite2D = sprites[ i ]
		var orig : Color = _sprite_default_modulates[ i ]
		var flash : Color = Color( orig.r * 2.5 , orig.g * 2.5 , orig.b * 2.5 , orig.a )
		var tw : Tween = create_tween()
		tw.tween_property( s , "modulate" , flash , 0.05 )
		tw.tween_property( s , "modulate" , orig , 0.05 )
	pass




func _physics_process(_delta: float) -> void:
	velocity.y += gravity * _delta * gravity_mulitplier
	velocity.y = clampf( velocity.y, -1000.0, max_fall_velocity ) 
	move_and_slide() 
	change_state( current_state.physics_process( _delta ) )

	pass



func initialize_states() -> void:
	states = []
	#收集所有状态
	for c in $States.get_children():
		if c is PlayerState:
			states.append( c )
			c.player = self
		pass
	
	if states.size() == 0:
		return
		
		
	#初始化所有状态
	for state in states:
		state.init()
		
		
	#设置第一个状态
	change_state( current_state )
	current_state.enter()
	$Label.text = current_state.name
	pass




func change_state( new_state: PlayerState ) -> void:
	if new_state == null:
		return
	elif new_state == current_state:
		return
		
	if current_state:
		current_state.exit()
		
	states.push_front( new_state )
	current_state.enter()
	states.resize( 3 )
	$Label.text = current_state.name
	pass




func update_direction() -> void:
	var prev_direction : Vector2 = direction
	var x_axis = Input.get_axis("left","right")
	var y_axis = Input.get_axis("up","down")
	direction = Vector2(x_axis,y_axis)
	if prev_direction.x != direction.x:
		attack_area.flip( direction.x )
		if direction.x < 0:
			sprite.flip_h = true
			sprite_2d_2.flip_h = true
			sprite_2d_2.position.x = 40
		elif direction.x > 0:
			sprite.flip_h = false
			sprite_2d_2.flip_h = false
			sprite_2d_2.position.x = 0
	pass





func add_debug_indicator( color : Color = Color.RED ) -> void:
	var d:Node2D = DEBUG_JUMP_INDICATOR.instantiate()
	get_tree().root.add_child( d )
	d.global_position = global_position
	d.modulate = color
	await get_tree().create_timer( 3.0 ).timeout
	d.queue_free()
	pass


func _on_player_healed( amount : float ) -> void:
	hp += amount
	pass


func _on_damage_taken( a : AttackArea ) -> void:
	if current_state == PlayerStateDeath:
		return
	hp -= a.damege
	damage_taken.emit()
	pass



func can_dash() -> bool:
	if dash == false or dash_count > 0 :
		return false
	#地面dash内置1秒CD：1秒内不能在地面再次闪避（空中dash不受影响）
	if is_on_floor() and Time.get_ticks_msec() - last_ground_dash_msec < GROUND_DASH_COOLDOWN_MSEC:
		return false
	return true
