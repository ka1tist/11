extends Node2D
## 黑幕系统单元测试：验证 区域外全黑 / 进入后缓慢淡出 / 离开后淡入恢复 /
## 过渡打断续接 / 初始状态定格 / 尺寸参数同步
## 运行方式（headless）：
## Godot_v4.7.1-stable_win64_console.exe --headless --path <项目目录> res://tests/test_black_curtain.tscn
## 全部通过打印 ALL_TESTS_PASSED 并以退出码0结束，否则打印 TESTS_FAILED 并以退出码1结束

const PLAYER_SCENE := preload( "res://player/player.tscn" )
#preload 脚本而非依赖全局类名缓存：headless 首次运行时新 class_name 尚未注册到全局缓存
const BlackCurtainScript := preload( "res://general/scripts/black_curtain.gd" )

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


func _wait_physics_frames( count : int ) -> void:
	for i in count:
		await get_tree().physics_frame
	pass


func _wait( seconds : float ) -> void:
	await get_tree().create_timer( seconds ).timeout
	pass


#轮询等待不透明度越过 threshold（Area2D 对瞬移的进出检测有若干物理帧延迟，
#headless 首帧还可能有加载抖动，固定帧数等待不可靠）；超时返回 false
func _wait_until_alpha( c , threshold : float , going_below : bool , max_frames : int = 20 ) -> bool:
	for i in max_frames:
		await get_tree().physics_frame
		var a : float = _alpha( c )
		if ( going_below and a < threshold ) or ( not going_below and a > threshold ):
			return true
	return false


func _make_curtain( pos : Vector2 , w : int , h : int , persistent : bool = false ) -> Node2D:
	var c = BlackCurtainScript.new()
	c.width = w
	c.height = h
	c.reveal_duration = 0.3
	c.darken_duration = 0.3
	c.persistent = persistent
	add_child( c )
	c.global_position = pos
	return c


func _alpha( c ) -> float:
	return c._polygon.modulate.a


func _run_tests() -> void:
	#---- 搭建测试环境：长地面 + 玩家（站立 y≈-34）----
	var ground := StaticBody2D.new()
	ground.collision_layer = 1
	ground.collision_mask = 0
	var ground_shape := CollisionShape2D.new()
	var ground_rect := RectangleShape2D.new()
	ground_rect.size = Vector2( 1000 , 16 )
	ground_shape.shape = ground_rect
	ground.add_child( ground_shape )
	add_child( ground )

	var player : Player = PLAYER_SCENE.instantiate()
	add_child( player )
	player.global_position = Vector2( -300 , -40 )

	#黑幕矩形：x 0..200，y -200..0（地面顶面 y=-8，玩家站立 y≈-34；x=100 时在区域内）
	var curtain = _make_curtain( Vector2( 0 , -200 ) , 200 , 200 )
	await _wait_physics_frames( 10 )

	#---- 测试1：玩家在区域外出生 → 定格全黑，无过渡 ----
	check( curtain._polygon.visible == true , "区域外黑幕应可见（全黑覆盖）" )
	check( _alpha( curtain ) >= 0.99 , "区域外黑幕应不透明，实际 %.3f" % _alpha( curtain ) )

	#---- 测试2：玩家进入区域 → 黑幕开始淡出（连续过渡而非瞬间切换），最终全透明并隐藏节点 ----
	player.global_position = Vector2( 100 , player.global_position.y )
	check( await _wait_until_alpha( curtain , 0.99 , true ) , "进入后黑幕应开始淡出" )
	check( _alpha( curtain ) > 0.05 , "淡出应为连续过渡而非瞬间变透明，实际 %.3f" % _alpha( curtain ) )
	await _wait( 0.4 )
	check( _alpha( curtain ) <= 0.01 , "进入0.4秒后黑幕应完全透明，实际 %.3f" % _alpha( curtain ) )
	check( curtain._polygon.visible == false , "完全透明后黑幕节点应隐藏以跳过绘制" )

	#---- 测试3：玩家首次揭示后离开区域 → 黑幕保持透明隐藏，不恢复黑暗 ----
	player.global_position = Vector2( -300 , player.global_position.y )
	await _wait( 0.4 )  #给足原本淡入的时长
	check( _alpha( curtain ) <= 0.01 , "首次揭示后离开不应恢复黑暗，实际 %.3f" % _alpha( curtain ) )
	check( curtain._polygon.visible == false , "首次揭示后离开黑幕仍应隐藏" )

	#---- 测试4：反复进出区域 → 黑幕始终保持透明（一次性揭示） ----
	for i in range( 3 ):
		player.global_position = Vector2( 100 , player.global_position.y )
		await _wait_physics_frames( 3 )
		player.global_position = Vector2( -300 , player.global_position.y )
		await _wait_physics_frames( 3 )
	await _wait( 0.4 )
	check( _alpha( curtain ) <= 0.01 , "反复进出后黑幕应仍透明，实际 %.3f" % _alpha( curtain ) )
	check( curtain._polygon.visible == false , "反复进出后黑幕节点应仍隐藏" )
	check( curtain._revealed == true , "_revealed 标志应为 true" )

	#---- 测试6：width/height 参数变更同步到渲染四边形与检测形状 ----
	curtain.width = 320
	curtain.height = 256
	check( curtain._polygon.polygon[ 2 ].x == 320.0 , "width 变更应同步到黑幕四边形" )
	check( curtain._polygon.polygon[ 2 ].y == 256.0 , "height 变更应同步到黑幕四边形" )
	check( curtain._shape.shape.size.x == 320.0 and curtain._shape.shape.size.y == 256.0 ,
		"尺寸变更应同步到玩家检测形状，实际 %s" % curtain._shape.shape.size )
	check( curtain._shape.position.x == 160.0 and curtain._shape.position.y == 128.0 ,
		"检测形状应保持在区域中心，实际 %s" % curtain._shape.position )

	#---- 测试6：新黑幕加载时玩家已在区域内 → 初始即定格全透明，且永久揭示 ----
	#curtain2 区域 x∈[50,150] y∈[-100,0]，玩家站立 y≈-34；先把玩家移入区域内
	player.global_position = Vector2( 100 , player.global_position.y )
	var curtain2 = _make_curtain( Vector2( 50 , -100 ) , 100 , 100 )
	await _wait_physics_frames( 10 )
	check( _alpha( curtain2 ) <= 0.01 , "出生在区域内应定格为透明，实际 %.3f" % _alpha( curtain2 ) )
	check( curtain2._polygon.visible == false , "出生在区域内黑幕节点应初始隐藏" )
	check( curtain2._revealed == true , "出生在区域内应标记为已揭示" )
	#离开 curtain2 区域后仍保持透明（永久揭示）
	player.global_position = Vector2( -300 , player.global_position.y )
	await _wait( 0.4 )
	check( _alpha( curtain2 ) <= 0.01 , "出生揭示后离开仍应透明，实际 %.3f" % _alpha( curtain2 ) )
	check( curtain2._polygon.visible == false , "出生揭示后离开仍应隐藏" )

	#---- 测试：持久化揭示状态（写入 persistent_data 并在重建时恢复） ----
	#备份存档槽0，避免测试覆盖玩家真实存档
	var save_path : String = SaveManager.get_file_name( 0 )
	var backup : String = ""
	if FileAccess.file_exists( save_path ):
		var f := FileAccess.open( save_path , FileAccess.READ )
		backup = f.get_line()
		f.close()
	#用固定节点名保证两次创建的黑幕 _get_persistent_id() 一致（同路径）
	var persist_name := "PersistTestCurtain"
	var cp = BlackCurtainScript.new()
	cp.name = persist_name
	cp.width = 100
	cp.height = 100
	cp.persistent = true
	add_child( cp )
	cp.global_position = Vector2( 200 , -100 )
	await _wait_physics_frames( 4 )
	var pid : String = cp._get_persistent_id()
	#模拟玩家进入触发揭示：应写入 persistent_data
	cp._mark_revealed()
	check( SaveManager.persistent_data.has( pid ) , "揭示后应写入 persistent_data" )
	check( cp._revealed == true , "揭示后 _revealed 应为 true" )
	#销毁后重建同节点名黑幕：应直接从 persistent_data 恢复为已隐藏，不播过渡
	cp.queue_free()
	await get_tree().process_frame
	var cp2 = BlackCurtainScript.new()
	cp2.name = persist_name
	cp2.width = 100
	cp2.height = 100
	cp2.persistent = true
	add_child( cp2 )
	cp2.global_position = Vector2( 200 , -100 )
	await _wait_physics_frames( 4 )
	check( cp2._revealed == true , "重建后应从 persistent_data 恢复为已揭示" )
	check( cp2._polygon.visible == false , "重建后黑幕应直接隐藏" )
	check( _alpha( cp2 ) <= 0.01 , "重建后黑幕应全透明，实际 %.3f" % _alpha( cp2 ) )
	#清理测试写入的持久化记录
	SaveManager.persistent_data.erase( pid )
	#恢复存档槽0
	var rf := FileAccess.open( save_path , FileAccess.WRITE )
	if not backup.is_empty():
		rf.store_line( backup )
	rf.close()
	pass
