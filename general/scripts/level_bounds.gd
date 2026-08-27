@tool
@icon("res://general/icons/level_bounds.svg")
class_name LevelBounds extends Node2D


@export_range(480,2048,16,"suffix:px") var width : int = 480 : set = _on_width_changed
@export_range(270,2048,16,"suffix:px") var height : int = 270 : set = _on_height_changed


func _ready() -> void:
	z_index = 256
	
	if Engine.is_editor_hint():
		return
	
	#检查获取摄像头的引用
	var camera : Camera2D = null
	
	while not camera:
		await get_tree().process_frame
		camera = get_viewport().get_camera_2d()
		
	var left : float = global_position.x
	var top : float = global_position.y
	var right : float = global_position.x + width
	var bottom : float = global_position.y + height
	
	camera.limit_left = int( left )
	camera.limit_top = int( top )
	camera.limit_right = int( right )
	camera.limit_bottom = int( bottom )

	#更新摄像头限制
	pass
	

func _draw() -> void:
	if Engine.is_editor_hint():
		var r : Rect2 = Rect2( Vector2.ZERO, Vector2(width,height) )
		draw_rect( r,Color(0.0,0.45,1.0,0.6),false,3 )
		draw_rect( r,Color(0.0,0.75,1.0),false,1 )
	pass


func _on_width_changed( new_width : int ) -> void:
	width = new_width
	queue_redraw()
	pass



func _on_height_changed( new_height : int ) -> void:
	height = new_height
	queue_redraw()
	pass
