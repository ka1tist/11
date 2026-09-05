extends Node2D
## 隐藏墙镜头限制单元测试：验证未破坏时镜头被钳制在墙x处、破坏后恢复levelbounds基础边界、
## 已破坏的持久化墙刷新时不再注册限制
## 运行方式（headless）：
## Godot_v4.7.1-stable_win64_console.exe --headless --path <项目目录> res://tests/test_camera_wall.tscn
## 全部通过打印 ALL_TESTS_PASSED 并以退出码0结束，否则打印 TESTS_FAILED 并以退出码1结束

const WALL_LEFT_SCENE := preload( "res://levels/props/隐藏左.tscn" )
const WALL_RIGHT_SCENE := preload( "res://levels/props/隐藏右.tscn" )

#基础边界：x∈[-100,300] y∈[-100,100]
const BOUNDS_POS := Vector2( -100 , -100 )
const BOUNDS_W := 400
const BOUNDS_H := 200

const WALL_RIGHT_X := 0.0    #隐藏右：未破坏时 limit_left 钳制到 0
const WALL_LEFT_X := 200.0   #隐藏左：未破坏时 limit_right 钳制到 200
const PAIR_X := 250.0        #持久化配对墙的x

var checks : int = 0
var failures : Array[String] = []


func check( cond : bool , msg : String ) -> void:
	checks += 1
	if cond == false:
		failures.append( msg )
		printerr( "FAIL: " + msg )
	pass


func _ready() -> void:
	await _run_tests()
	if failures.is_empty():
		print( "ALL_TESTS_PASSED (%d checks)" % checks )
	else:
		print( "TESTS_FAILED: %d/%d checks failed" % [ failures.size() , checks ] )
	get_tree().quit( 0 if failures.is_empty() else 1 )
	pass


func _wait_process_frames( count : int ) -> void:
	for i in count:
		await get_tree().process_frame
	pass


func _spawn_wall( scene : PackedScene , wall_name : String , x : float ) -> Breakable:
	var wall : Breakable = scene.instantiate()
	wall.name = wall_name
	add_child( wall )
	wall.global_position = Vector2( x , 0 )
	return wall


func _run_tests() -> void:
	#---- 搭建测试环境：镜头 + LevelBounds + 左右隐藏墙 ----
	var camera := Camera2D.new()
	camera.name = "Camera"
	add_child( camera )
	camera.make_current()
	camera.global_position = Vector2( 100 , 0 )

	var bounds := LevelBounds.new()
	bounds.name = "Bounds"
	bounds.position = BOUNDS_POS
	bounds.width = BOUNDS_W
	bounds.height = BOUNDS_H
	add_child( bounds )

	var wall_left : Breakable = _spawn_wall( WALL_LEFT_SCENE , "WallLeft" , WALL_LEFT_X )
	var wall_right : Breakable = _spawn_wall( WALL_RIGHT_SCENE , "WallRight" , WALL_RIGHT_X )

	await _wait_process_frames( 5 )

	#---- 测试1：墙体场景的镜头限制方向配置正确 ----
	check( wall_left.camera_limit_side == 2 , "隐藏左应配置为2(限制镜头右边界)，实际 %s" % wall_left.camera_limit_side )
	check( wall_right.camera_limit_side == 1 , "隐藏右应配置为1(限制镜头左边界)，实际 %s" % wall_right.camera_limit_side )
	check( bounds._camera != null , "LevelBounds应已获取镜头引用" )

	#---- 测试2：未破坏时镜头被钳制在墙x处，其余边界遵循LevelBounds基础设置 ----
	check( camera.limit_left == int( WALL_RIGHT_X ) ,
		"未破坏时镜头左边界应钳制在隐藏右x=%s，实际 %s" % [ WALL_RIGHT_X , camera.limit_left ] )
	check( camera.limit_right == int( WALL_LEFT_X ) ,
		"未破坏时镜头右边界应钳制在隐藏左x=%s，实际 %s" % [ WALL_LEFT_X , camera.limit_right ] )
	check( camera.limit_top == int( BOUNDS_POS.y ) , "上下边界应遵循LevelBounds，limit_top实际 %s" % camera.limit_top )
	check( camera.limit_bottom == int( BOUNDS_POS.y + BOUNDS_H ) , "上下边界应遵循LevelBounds，limit_bottom实际 %s" % camera.limit_bottom )

	#---- 测试2b：levelbounds(400x200)小于视口时，zoom自动收缩使可见范围以levelbounds为准 ----
	var vp_size : Vector2 = camera.get_viewport_rect().size
	var visible_size : Vector2 = vp_size / camera.zoom
	check( visible_size.x <= BOUNDS_W + 0.01 and visible_size.y <= BOUNDS_H + 0.01 ,
		"levelbounds小于视口时可见范围应收缩至边界内，可见尺寸 %s (zoom=%s)" % [ visible_size , camera.zoom ] )
	check( camera.zoom.x >= 1.0 , "zoom收缩不应小于1（不放大画面），实际 %s" % camera.zoom.x )

	#---- 测试3：破坏隐藏左 → 右边界平滑过渡到levelbounds基础值，左边界不受影响 ----
	wall_left.destroy()
	check( camera.limit_right == int( WALL_LEFT_X ) , "破坏瞬间右边界应保持墙位置（过渡未开始），实际 %s" % camera.limit_right )
	check( camera.limit_left == int( WALL_RIGHT_X ) , "破坏隐藏左后镜头左边界应保持墙限制，实际 %s" % camera.limit_left )
	await get_tree().create_timer( 0.15 ).timeout
	check( camera.limit_right > int( WALL_LEFT_X ) and camera.limit_right < BOUNDS_POS.x + BOUNDS_W ,
		"过渡进行中右边界应介于墙x=%s与基础值%s之间，实际 %s" % [ WALL_LEFT_X , BOUNDS_POS.x + BOUNDS_W , camera.limit_right ] )
	await get_tree().create_timer( 0.5 ).timeout
	check( camera.limit_right == BOUNDS_POS.x + BOUNDS_W ,
		"过渡完成后右边界应恢复为基础右边界%s，实际 %s" % [ BOUNDS_POS.x + BOUNDS_W , camera.limit_right ] )

	#---- 测试4：破坏隐藏右 → 左边界也平滑过渡恢复levelbounds基础值 ----
	wall_right.destroy()
	check( camera.limit_left == int( WALL_RIGHT_X ) , "破坏瞬间左边界应保持墙位置（过渡未开始），实际 %s" % camera.limit_left )
	check( camera.limit_right == BOUNDS_POS.x + BOUNDS_W , "破坏隐藏右后右边界应保持基础值，实际 %s" % camera.limit_right )
	await get_tree().create_timer( 0.6 ).timeout
	check( camera.limit_left == int( BOUNDS_POS.x ) ,
		"过渡完成后左边界应恢复为基础左边界%s，实际 %s" % [ BOUNDS_POS.x , camera.limit_left ] )

	#---- 测试5：存档中已破坏的持久化墙刷新时直接消失，不注册镜头限制 ----
	var wall_a : Breakable = _spawn_wall( WALL_LEFT_SCENE , "PA" , PAIR_X )
	await _wait_process_frames( 2 )
	check( camera.limit_right == int( PAIR_X ) , "新墙注册后镜头右边界应钳制到%s，实际 %s" % [ PAIR_X , camera.limit_right ] )

	var pid : String = wall_a._get_persistent_id()
	SaveManager.persistent_data[ pid ] = true
	remove_child( wall_a )
	wall_a.free()

	var wall_b : Breakable = _spawn_wall( WALL_LEFT_SCENE , "PA" , PAIR_X )  #同路径 → 同存档id
	check( wall_b.is_queued_for_deletion() , "存档中已破坏的持久化墙刷新后应直接queue_free" )
	await _wait_process_frames( 2 )
	check( camera.limit_right == int( PAIR_X ) , "已破坏的持久化墙不应注册镜头限制，右边界应保持%s，实际 %s" % [ PAIR_X , camera.limit_right ] )

	#---- 测试6：levelbounds不小于视口时，zoom保持1不收缩 ----
	var camera2 := Camera2D.new()
	camera2.name = "Camera2"
	add_child( camera2 )
	camera2.make_current()
	camera2.global_position = Vector2( 0 , 0 )

	var big_bounds := LevelBounds.new()
	big_bounds.name = "BigBounds"
	big_bounds.position = Vector2( -1024 , -1024 )
	big_bounds.width = 2048
	big_bounds.height = 2048
	add_child( big_bounds )

	await _wait_process_frames( 5 )
	check( camera2.zoom == Vector2.ONE , "levelbounds不小于视口时zoom应保持1，实际 %s" % camera2.zoom )
	check( camera2.limit_left == -1024 and camera2.limit_right == 1024 , "大边界镜头limit应遵循levelbounds，实际 %s/%s" % [ camera2.limit_left , camera2.limit_right ] )
	pass
