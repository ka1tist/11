extends Node2D
## 凋落物磁吸单元测试：范围外不受吸 → 玩家靠近后吸取激活 → 飞向玩家并被拾取
## 运行方式（headless）：
## Godot_v4.7.1-stable_win64_console.exe --headless --path <项目目录> res://tests/test_loot_magnet.tscn
## 全部通过打印 ALL_TESTS_PASSED 并以退出码0结束，否则打印 TESTS_FAILED 并以退出码1结束

const PLAYER_SCENE := preload( "res://player/player.tscn" )
const COIN_SCENE := preload( "res://general/pickup/coin_pickup.tscn" )
const HEART_SCENE := preload( "res://general/pickup/health_pickup.tscn" )

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
	#---- 搭建测试环境：地面 + 玩家 + 金币 + 红心 ----
	var ground := StaticBody2D.new()
	ground.name = "Ground"
	ground.collision_layer = 1
	ground.collision_mask = 0
	var ground_shape := CollisionShape2D.new()
	var ground_rect := RectangleShape2D.new()
	ground_rect.size = Vector2( 800 , 16 )
	ground_shape.shape = ground_rect
	ground.add_child( ground_shape )
	add_child( ground )
	ground.global_position = Vector2( 0 , 0 )  #地面顶面位于 y = -8

	var player : Player = PLAYER_SCENE.instantiate()
	add_child( player )
	player.global_position = Vector2( 0 , -40 )  #下落到地面站立
	player.loot_magnet_range = 60.0  #测试用较大范围：磁吸圆心在角色中心（脚底上方26px），地面凋落物距圆心较远

	var coin = COIN_SCENE.instantiate()
	add_child( coin )
	coin.global_position = Vector2( 150 , -20 )  #落地后距磁吸圆心约159像素，超出范围60

	var heart = HEART_SCENE.instantiate()
	add_child( heart )
	heart.global_position = Vector2( -150 , -20 )

	await _wait_physics_frames( 40 )  #等待凋落物落地弹跳

	#---- 测试1：范围外凋落物不被吸取 ----
	check( is_instance_valid( coin ) and coin._attracted == false , "范围外金币不应被吸取" )
	check( is_instance_valid( heart ) and heart._attracted == false , "范围外红心不应被吸取" )

	#---- 测试2：玩家进入吸取范围 → 凋落物被激活追踪 ----
	player.global_position = Vector2( 120 , -26 )  #磁吸圆心(120,-52)与金币距离约49 < 60
	await _wait_physics_frames( 3 )
	check( is_instance_valid( coin ) and coin._attracted , "进入吸取范围后金币应被激活追踪" )
	check( is_instance_valid( heart ) and heart._attracted == false , "范围外红心仍不应被吸取" )

	#---- 测试3：金币飞向玩家并被拾取（金币数+1、节点移除）----
	var coin_before : int = player.coin
	await _wait_physics_frames( 60 )
	check( is_instance_valid( coin ) == false , "金币被吸到玩家身上后应被拾取移除" )
	check( player.coin == coin_before + 1 , "拾取后玩家金币数应+1，实际 %s" % player.coin )

	#---- 测试4：红心同样可被磁吸拾取 ----
	player.global_position = Vector2( -120 , -26 )  #磁吸圆心(-120,-52)与红心距离约49 < 60
	await _wait_physics_frames( 60 )
	check( is_instance_valid( heart ) == false , "红心被吸到玩家身上后应被拾取移除" )
	pass
