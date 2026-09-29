@tool
@icon("res://general/icons/level_bounds.svg")
class_name LevelBounds extends Node2D


@export_range(240,4096,16,"suffix:px") var width : int = 240 : set = _on_width_changed
@export_range(135,2048,16,"suffix:px") var height : int = 135 : set = _on_height_changed

#基础边界矩形：隐藏墙被破坏后，镜头限制恢复到这里
var _base_left : int = 0
var _base_top : int = 0
var _base_right : int = 0
var _base_bottom : int = 0

#未破坏隐藏墙的注册表：id -> 限制x坐标
#_wall_left_limits：限制镜头左边界（side=1，如"隐藏右"）；_wall_right_limits：限制镜头右边界（side=2，如"隐藏左"）
var _wall_left_limits : Dictionary = {}
var _wall_right_limits : Dictionary = {}

var _camera : Camera2D = null

#破坏墙后镜头限制的平滑过渡时长
const LIMIT_ANIM_DURATION : float = 0.4
var _camera_tween : Tween = null
var _limits_applied_once : bool = false


func _ready() -> void:
	z_index = 256
	add_to_group( "level_bounds" )

	#先记录基础边界，供隐藏墙破坏后恢复整体边界使用
	_base_left = int( global_position.x )
	_base_top = int( global_position.y )
	_base_right = int( global_position.x + width )
	_base_bottom = int( global_position.y + height )

	if Engine.is_editor_hint():
		return

	#检查获取摄像头的引用
	while not _camera:
		await get_tree().process_frame
		_camera = get_viewport().get_camera_2d()

	_apply_camera_limits()


#注册一面隐藏墙的镜头限制（side=1限制镜头左边界，side=2限制镜头右边界；x为墙的x轴位置）
#镜头未就绪时仅登记，待镜头就绪后统一应用
func set_camera_wall_limit( id : String , side : int , x : float ) -> void:
	if side == 1:
		_wall_left_limits[ id ] = int( x )
	elif side == 2:
		_wall_right_limits[ id ] = int( x )
	_apply_camera_limits()
	pass


#隐藏墙被破坏后注销其镜头限制：该侧平滑过渡恢复为levelbounds基础边界，其余未破坏墙的限制保留
func clear_camera_wall_limit( id : String , side : int ) -> void:
	var erased : bool = false
	if side == 1:
		erased = _wall_left_limits.erase( id )
	elif side == 2:
		erased = _wall_right_limits.erase( id )
	if erased:
		_apply_camera_limits( true )
	pass


#按基础边界+所有未破坏隐藏墙重算镜头限制
#animated=true（破坏墙）时，变化的侧边从当前值平滑过渡到目标值，镜头随玩家移动渐进展开新区域
#初始应用/墙体注册用立即生效，避免场景加载时镜头从默认边界大幅滑动
func _apply_camera_limits( animated : bool = false ) -> void:
	if _camera == null:
		return

	var target_left : int = _base_left
	var target_top : int = _base_top
	var target_right : int = _base_right
	var target_bottom : int = _base_bottom

	#左隐藏墙取最靠右（限制最强）的墙位置，并夹在基础边界内防止越界配置
	for x in _wall_left_limits.values():
		target_left = maxi( target_left , clampi( x , _base_left , _base_right ) )
	#右隐藏墙取最靠左（限制最强）的墙位置
	for x in _wall_right_limits.values():
		target_right = mini( target_right , clampi( x , _base_left , _base_right ) )

	#打断进行中的过渡，从当前值重新出发，连续破坏/注册时也不会跳变
	if _camera_tween != null and _camera_tween.is_valid():
		_camera_tween.kill()

	if animated and _limits_applied_once:
		_camera_tween = create_tween()
		_camera_tween.set_parallel( true )
		_camera_tween.set_trans( Tween.TRANS_SINE )
		_camera_tween.set_ease( Tween.EASE_OUT )
		if _camera.limit_left != target_left:
			_camera_tween.tween_property( _camera , "limit_left" , target_left , LIMIT_ANIM_DURATION )
		if _camera.limit_right != target_right:
			_camera_tween.tween_property( _camera , "limit_right" , target_right , LIMIT_ANIM_DURATION )
		_camera.limit_top = target_top
		_camera.limit_bottom = target_bottom
	else:
		_camera.limit_left = target_left
		_camera.limit_top = target_top
		_camera.limit_right = target_right
		_camera.limit_bottom = target_bottom

	_fit_camera_zoom_to_bounds()
	_limits_applied_once = true
	pass


#levelbounds任一轴小于视口可见范围时，增大zoom收缩视野，使镜头可见范围以levelbounds为准
#（视野比边界大时limit钳制无法把视野约束在边界内，会看到边界外区域）
func _fit_camera_zoom_to_bounds() -> void:
	var viewport_size : Vector2 = _camera.get_viewport_rect().size
	var bounds_size : Vector2 = Vector2( _base_right - _base_left , _base_bottom - _base_top )
	if bounds_size.x <= 0.0 or bounds_size.y <= 0.0:
		return
	#可见世界尺寸 = 视口尺寸/zoom；要装进边界需 zoom >= 视口/边界，两轴取最大以保持画面比例
	var needed : float = maxf( viewport_size.x / bounds_size.x , viewport_size.y / bounds_size.y )
	#每关确定性地重设zoom：不小于1（不放大画面），仅当边界装不下视口时收缩视野
	_camera.zoom = Vector2.ONE * maxf( 1.0 , needed )
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
