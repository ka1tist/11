@tool
@icon( "res://general/icons/breakable.svg" )
class_name Breakable extends Node2D

signal  destroyed
signal  damage_taken

@export var hp : float = 3
@export var fixed_hit_count : bool = false


#持久化：破坏后记录到SaveManager.persistent_data，切换地图/读档不再刷新，新游戏时重置
@export var persistent : bool = false

#镜头限制（可选）：未被破坏时将镜头对应侧边界钳制在本墙x坐标处，破坏后由LevelBounds恢复整体边界
#0=无 1=限制镜头左边界（如"隐藏右"，墙后区域在墙左侧） 2=限制镜头右边界（如"隐藏左"，墙后区域在墙右侧）
@export_enum( "无" , "限制镜头左边界" , "限制镜头右边界" ) var camera_limit_side : int = 0

@export_category( "Particles" )
@export var emission_offset : Vector2 = Vector2.ZERO
@export var hit_particles : Array[ HitParticleSettings ]
@export var destroy_particles : Array[ HitParticleSettings ]

@export_category( "Audio" )
@export var hit_audio : AudioStream = preload("uid://dedlvms7fc0q2")
@export var destroy_audio : AudioStream = preload("uid://i7p3xk1bocdd")


var hit_count : int = 0


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	#已破坏过的持久化墙体直接消失，不再刷新（queue_free后不会注册镜头限制）
	if persistent and SaveManager.persistent_data.has( _get_persistent_id() ):
		queue_free()
		return
		
	for c in get_children():
		if c is DamageArea:
			c.damage_taken.connect( _on_damage_taken )


	#挂接镜头限制：注册延迟一帧执行，确保LevelBounds已就绪
	if camera_limit_side != 0:
		destroyed.connect( _release_camera_limit )
		_apply_camera_limit.call_deferred()
	pass


#向LevelBounds注册镜头限制，未破坏期间镜头该侧边界钳制在本墙x坐标处
func _apply_camera_limit() -> void:
	if camera_limit_side == 0 or is_queued_for_deletion():
		return
	var bounds : LevelBounds = get_tree().get_first_node_in_group( "level_bounds" )
	if bounds:
		bounds.set_camera_wall_limit( str( get_path() ) , camera_limit_side , global_position.x )
	pass


#墙被破坏时注销镜头限制：镜头该侧平滑扩展回levelbounds边界
func _release_camera_limit() -> void:
	var bounds : LevelBounds = get_tree().get_first_node_in_group( "level_bounds" )
	if bounds:
		bounds.clear_camera_wall_limit( str( get_path() ) , camera_limit_side )
	pass


#生成当前墙体在存档中的唯一ID：场景路径+节点路径
func _get_persistent_id() -> String:
	var scene_root : Node = get_tree().current_scene
	if scene_root:
		return str( scene_root.scene_file_path ) + "|" + str( scene_root.get_path_to( self ) )
	return str( get_path() )


#外部直接销毁（如ground_slam）时调用，走与正常击破一致的完整流程（信号/音效/粒子/淡出），并确保持久化状态被记录
func destroy( dir : Vector2 = Vector2.UP ) -> void:
	if persistent:
		SaveManager.persistent_data[ _get_persistent_id() ] = true
	destroyed.emit()
	var pos : Vector2 = global_position + emission_offset
	Audio.play_spatial_sound( destroy_audio , pos )
	for p in destroy_particles:
		VisualEffects.hit_particles( pos , dir , p )
	clear_collision()
	var tween : Tween = create_tween()
	tween.tween_property( self , "modulate" , Color( modulate , 0 ) , 0.4 )
	tween.finished.connect( queue_free )


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
		hit_count += 1
		damage_taken.emit()
		Audio.play_spatial_sound( hit_audio , pos )
		for p in hit_particles:
			VisualEffects.hit_particles( pos , dir , p )
	else:
		#走destroy()统一击破流程：发destroyed信号、播放音效粒子、清除碰撞并淡出
		destroy( dir )
		
	pass



func clear_collision() -> void:
	for c in get_children():
		if c is StaticBody2D or c is DamageArea:
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
