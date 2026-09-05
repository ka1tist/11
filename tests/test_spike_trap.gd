extends Node2D
## 地刺陷阱单元测试：验证扣血 → 全屏黑屏 → 保持0.5秒 → 传送回安全位置 的触发时机与执行效果
## 运行方式（headless）：
## Godot_v4.7.1-stable_win64.exe --headless --path <项目目录> res://tests/test_spike_trap.tscn
## 全部通过打印 ALL_TESTS_PASSED 并以退出码0结束，否则打印 TESTS_FAILED 并以退出码1结束

const SPIKE_SCENE := preload( "res://levels/props/地刺.tscn" )
const PLAYER_SCENE := preload( "res://player/player.tscn" )

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


func _run_tests() -> void:
	#---- 搭建测试环境：地面 + 玩家 + 地刺 ----
	var ground := StaticBody2D.new()
	ground.name = "Ground"
	ground.collision_layer = 1
	ground.collision_mask = 0
	var ground_shape := CollisionShape2D.new()
	var ground_rect := RectangleShape2D.new()
	ground_rect.size = Vector2( 400 , 16 )
	ground_shape.shape = ground_rect
	ground.add_child( ground_shape )
	add_child( ground )
	ground.global_position = Vector2( 0 , 0 )  #地面顶面位于 y = -8

	var player : Player = PLAYER_SCENE.instantiate()
	add_child( player )
	player.global_position = Vector2( -60 , -40 )  #下落到地面站立

	var spike : Node2D = SPIKE_SCENE.instantiate()
	add_child( spike )
	spike.global_position = Vector2( 0 , -8 )  #判定范围底边与地面顶面平齐

	await _wait_physics_frames( 30 )

	#---- 测试1：进入前状态（满血 / 无黑屏 / 安全位置已记录）----
	check( player.hp == 20 , "进入前玩家应为满血20，实际 %s" % player.hp )
	check( spike.get_overlay_alpha() == 0.0 , "进入前不应有黑屏" )
	check( spike._has_safe_position , "进入前应已记录安全位置" )
	check( spike.safe_position.distance_to( player.global_position ) < 1.0 ,
		"安全位置应等于玩家当前站立位置" )

	#---- 测试2：进入判定范围 → 立即扣除10点生命并进入受击状态 ----
	var safe_pos : Vector2 = spike.safe_position
	player.global_position = Vector2( 0 , player.global_position.y )
	await _wait_physics_frames( 3 )
	check( player.hp == 10 , "进入判定范围后应扣除10点生命，实际 %s" % player.hp )
	check( player.current_state is PlayerStateTakeDamage , "应进入现有受击状态TakeDamage" )

	#---- 测试3：黑屏淡入（进入后约0.2秒应达到全黑）----
	await get_tree().create_timer( 0.2 ).timeout
	check( spike.get_overlay_alpha() == 1.0 , "进入后0.2秒内应达到全黑" )

	#---- 测试4：全黑期间已传送回进入前的安全位置 ----
	check( player.global_position.distance_to( safe_pos ) < 4.0 ,
		"黑屏期间应传送回安全位置 %s，实际 %s" % [ safe_pos , player.global_position ] )

	#---- 测试5：全黑保持约0.5秒（进入后约0.55秒时仍应全黑）----
	await get_tree().create_timer( 0.35 ).timeout
	check( spike.get_overlay_alpha() == 1.0 , "全黑应保持0.5秒（0.55秒时仍应全黑）" )

	#---- 测试6：黑屏结束后恢复正常显示，玩家仍位于安全位置 ----
	await get_tree().create_timer( 0.4 ).timeout
	check( spike.get_overlay_alpha() == 0.0 , "黑屏结束后应恢复正常显示" )
	check( player.global_position.distance_to( safe_pos ) < 4.0 ,
		"恢复显示后玩家应仍位于安全位置" )
	pass
