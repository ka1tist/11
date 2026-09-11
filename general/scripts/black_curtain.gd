@tool
@icon("res://general/icons/black_curtain.svg")
class_name BlackCurtain extends Node2D

## 黑幕区域：尺寸/位置设置方式与 LevelBounds 完全一致——节点原点即矩形左上角，
## 用导出的 width/height 调整大小，拖节点调位置。
## 玩家在区域外：区域内画面被纯黑覆盖（黑幕不透明），区域外画面不受影响；
## 玩家首次进入区域：黑幕缓慢淡出至全透明，之后永久隐藏（离开区域也不再恢复黑暗）。
## 性能：世界空间 Polygon2D 单四边形覆盖区域（随镜头自动滚动，无需每帧算屏幕坐标）；
## Area2D 进出信号驱动过渡，无每帧轮询；全透明时 visible=false 彻底跳过绘制。

@export_range( 120 , 2048 , 16 , "suffix:px" ) var width : int = 120 : set = _on_width_changed
@export_range( 135 , 2048 , 16 , "suffix:px" ) var height : int = 135 : set = _on_height_changed
##玩家进入后黑幕淡出（揭示内部）时长（秒）
@export_range( 0.1 , 5.0 , 0.1 , "suffix:s" ) var reveal_duration : float = 0.8
##玩家离开后黑幕淡入（恢复黑暗）时长（秒）
@export_range( 0.1 , 5.0 , 0.1 , "suffix:s" ) var darken_duration : float = 0.6
##持久化：首次揭示后写入存档，切换地图/死亡重生/读档均保持已隐藏，新游戏时重置
@export var persistent : bool = true

#玩家本体碰撞层（player.tscn 根 CharacterBody2D collision_layer=16）
const PLAYER_LAYER : int = 16
#黑幕覆盖所有世界内容（地块/道具/角色 z=0~1、前景视差层 z=2~4）；HUD 走 CanvasLayer 不受影响
const CURTAIN_Z : int = 1
const MORPH_OUT = preload("uid://qe710of8dx3c")

var _polygon : Polygon2D = null
var _area : Area2D = null
var _shape : CollisionShape2D = null
var _tween : Tween = null
#玩家首次进入后永久揭示：离开区域也不再恢复黑暗
var _revealed : bool = false


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_build_polygon()
	_build_area()
	#读档恢复：若该黑幕已被揭示过，直接永久隐藏，不再按玩家位置判定、不播过渡
	if persistent and SaveManager.persistent_data.has( _get_persistent_id() ):
		_revealed = true
		_polygon.modulate.a = 0.0
		_polygon.visible = false
		return
	#初始状态等物理就绪后按玩家所在位置直接定格，避免场景加载/出生在区域内时误播淡入淡出
	await get_tree().physics_frame
	await get_tree().physics_frame
	_snap_to_player()
	pass


#世界空间黑色四边形：随场景变换与镜头自动滚动，z_index 保证盖住区域内一切世界内容
func _build_polygon() -> void:
	_polygon = Polygon2D.new()
	_polygon.name = "Curtain"
	_polygon.z_index = CURTAIN_Z
	_polygon.color = Color("#0c070b")
	_polygon.polygon = _rect_points()
	add_child( _polygon )
	pass


#只监测玩家层的进出：信号驱动，不做每帧轮询
func _build_area() -> void:
	_area = Area2D.new()
	_area.name = "Detector"
	_area.collision_layer = 0
	_area.collision_mask = PLAYER_LAYER
	_area.monitoring = true
	_shape = CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2( width , height )
	_shape.shape = rect
	_shape.position = Vector2( width , height ) * 0.5
	_area.add_child( _shape )
	_area.body_entered.connect( _on_body_entered )
	_area.body_exited.connect( _on_body_exited )
	add_child( _area )
	pass


func _rect_points() -> PackedVector2Array:
	return PackedVector2Array( [
		Vector2( 0 , 0 ) ,
		Vector2( width , 0 ) ,
		Vector2( width , height ) ,
		Vector2( 0 , height ) ,
	] )


func _on_body_entered( body : Node2D ) -> void:
	if body is Player:
		if not _revealed:
			Audio.play_spatial_sound( MORPH_OUT , global_position  )
			_mark_revealed()
		_set_dark( false )
	pass


func _on_body_exited( body : Node2D ) -> void:
	if not body is Player:
		return
	#首次揭示后永久隐藏，离开区域不再恢复黑暗
	if _revealed:
		return
	_set_dark( true )
	pass


#场景加载时玩家可能直接出生在黑幕内/外：按实际位置定格初始透明度，不做过渡
func _snap_to_player() -> void:
	var player := get_tree().get_first_node_in_group( "Player" ) as Player
	var dark : bool = true
	if player != null:
		dark = not _global_rect().has_point( player.global_position )
		#出生就在区域内视为已揭示，离开后也不再恢复黑暗
		if not dark:
			_mark_revealed()
	_kill_tween()
	_polygon.modulate.a = 1.0 if dark else 0.0
	_polygon.visible = dark
	pass


#标记为已揭示并持久化：写入存档后切换地图/死亡重生/读档均保持隐藏
#用 save_progress() 而非 save_game()，避免覆盖存档点位置（同钻石/宝箱约定）
func _mark_revealed() -> void:
	_revealed = true
	if persistent:
		SaveManager.persistent_data[ _get_persistent_id() ] = true
		SaveManager.save_progress()
	pass


#与 LevelBounds 一致：假设节点无缩放/旋转，全局矩形=原点+width/height
func _global_rect() -> Rect2:
	return Rect2( global_position , Vector2( width , height ) )


#dark=true 淡入至纯黑（玩家在区域外）；dark=false 淡出至透明（玩家在区域内）
func _set_dark( dark : bool ) -> void:
	_kill_tween()
	#变不透明时确保节点可见；变透明时不强制 visible，避免把已隐藏的黑幕重新显示
	if dark:
		_polygon.visible = true
	_tween = create_tween()
	_tween.tween_property(
		_polygon , "modulate:a" , 1.0 if dark else 0.0 ,
		darken_duration if dark else reveal_duration )
	if not dark:
		#淡出完成后彻底隐藏节点跳过绘制；淡入在开头已重新 visible=true，被打断也不会残留隐藏
		_tween.tween_callback( func() -> void:
			if _polygon.modulate.a <= 0.01:
				_polygon.visible = false )
	pass


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	pass


func _refresh_size() -> void:
	if Engine.is_editor_hint():
		queue_redraw()
		return
	if _polygon != null:
		_polygon.polygon = _rect_points()
	if _shape != null and _shape.shape is RectangleShape2D:
		_shape.shape.size = Vector2( width , height )
		_shape.position = Vector2( width , height ) * 0.5
	queue_redraw()
	pass


func _draw() -> void:
	if Engine.is_editor_hint():
		var r : Rect2 = Rect2( Vector2.ZERO , Vector2( width , height ) )
		draw_rect( r , Color( 0.0 , 0.0 , 0.0 , 0.45 ) , true )
		draw_rect( r , Color( 0.0 , 0.0 , 0.0 , 0.9 ) , false , 3 )
		draw_rect( r , Color( 0.65 , 0.65 , 0.8 , 1.0 ) , false , 1 )
	pass


func _on_width_changed( new_width : int ) -> void:
	width = new_width
	_refresh_size()
	pass


func _on_height_changed( new_height : int ) -> void:
	height = new_height
	_refresh_size()
	pass


#生成当前黑幕在存档中的唯一ID：场景路径+节点路径，与 Breakable/Treasure/钻石 持久化键格式一致
func _get_persistent_id() -> String:
	var scene_root : Node = get_tree().current_scene
	if scene_root:
		return str( scene_root.scene_file_path ) + "|" + str( scene_root.get_path_to( self ) )
	return str( get_path() )
