extends Node2D
## 飞行敌人死亡/眩晕状态测试（headless 运行）：
## 1. 幽灵受致命伤害后进入 ESFlyDeath 状态
## 2. 死亡期间原地悬停：X轴不变、Y轴不下落（重力被抵消）、速度为零
## 3. 死亡动画播完后敌人被 queue_free 销毁（继承 es_death 基础流程）
## 4. 受击未死进入 ESFlyStun：原地停顿（无击退位移、不下坠），动画播完恢复巡逻
## 运行：Godot_v4.7.1-stable_win64_console.exe --headless --path <项目> res://tests/test_fly_death.tscn

const GHOST_SCENE := preload( "res://enemies/ghost/ghost.tscn" )
#新 class_name 首次 headless 运行未注册全局类缓存，须 preload 而非用全局类型名
const ESFlyDeathScript := preload( "res://enemies/scripts/states/es_fly_death.gd" )
const ESFlyStunScript := preload( "res://enemies/scripts/states/es_fly_stun.gd" )

var _fails : int = 0
var _checks : int = 0


func _ready() -> void:
	await _run_tests()
	if _fails == 0:
		print( "ALL_TESTS_PASSED (%d checks)" % _checks )
	else:
		print( "TESTS_FAILED: %d/%d checks failed" % [ _fails , _checks ] )
	get_tree().quit( 1 if _fails > 0 else 0 )
	pass


func _check( cond : bool , msg : String ) -> void:
	_checks += 1
	if cond == false:
		_fails += 1
		print( "FAIL: " + msg )
	pass


func _run_tests() -> void:
	#---- 测试1：致命伤害后进入 ESFlyDeath 状态 ----
	var ghost = GHOST_SCENE.instantiate()
	add_child( ghost )
	ghost.global_position = Vector2( 300 , -150 )  #悬空放置，下方无地面
	for i in 5:
		await get_tree().physics_frame
	_check( ghost.state_machine.current_state is ESFly , "死亡前应处于 ESFly 巡逻状态" )

	var pos_before : Vector2 = ghost.global_position
	var killer := AttackArea.new()
	killer.damege = 999
	ghost._on_damage_taken( killer )  #直接触发致命伤害（等价 DamageArea.take_damage 调用路径）
	#注意：killer 不可在此处释放——决策引擎下一帧还要读 blackboard.damage_source，
	#悬空引用会让 decide() 失败、永远进不了死亡态；须等 enter() 清空 damage_source 后再释放

	#等状态机在下一物理帧切换到死亡态
	for i in 3:
		await get_tree().physics_frame
	_check( ghost.state_machine.current_state is ESFlyDeathScript , "致命伤害后应进入 ESFlyDeath 状态" )
	killer.free()  #damage_source 已被 enter() 清空，此时可安全释放

	#---- 测试2：死亡期间原地悬停（X固定、不下落、速度为零）----
	for i in 30:
		await get_tree().physics_frame
		if is_instance_valid( ghost ) == false or ghost.state_machine.current_state is ESFlyDeathScript == false:
			break
	var pos_after : Vector2 = ghost.global_position
	_check( absf( pos_after.x - pos_before.x ) <= 1.0 , "死亡期间X轴应保持不变（偏移=%.2f）" % absf( pos_after.x - pos_before.x ) )
	_check( absf( pos_after.y - pos_before.y ) <= 1.0 , "死亡期间Y轴不应下落（位移=%.2f）" % absf( pos_after.y - pos_before.y ) )
	if is_instance_valid( ghost ):
		_check( ghost.velocity == Vector2.ZERO , "死亡期间速度应为零，实际=%s" % str( ghost.velocity ) )

	#---- 测试3：动画播完后敌人销毁（继承 es_death 的 queue_free 流程）----
	var freed := false
	for i in 120:
		await get_tree().physics_frame
		if is_instance_valid( ghost ) == false:
			freed = true
			break
	_check( freed , "死亡动画结束后敌人应被 queue_free 销毁" )
	if is_instance_valid( ghost ):
		ghost.queue_free()

	#---- 测试4：受击未死进入 ESFlyStun，原地停顿后恢复巡逻 ----
	var ghost2 = GHOST_SCENE.instantiate()
	add_child( ghost2 )
	ghost2.global_position = Vector2( -300 , -150 )  #悬空放置，下方无地面
	for i in 5:
		await get_tree().physics_frame
	_check( ghost2.state_machine.current_state is ESFly , "受击前应处于 ESFly 巡逻状态" )

	var pos2 : Vector2 = ghost2.global_position
	var killer2 := AttackArea.new()
	killer2.damege = 1  #非致命伤害（ghost health=3）
	ghost2._on_damage_taken( killer2 )
	#killer2 不可立即释放——决策引擎下一帧还要读 blackboard.damage_source

	for i in 3:
		await get_tree().physics_frame
	_check( ghost2.state_machine.current_state is ESFlyStunScript , "受击未死后应进入 ESFlyStun 状态" )
	killer2.free()  #damage_source 已被 start() 清空，此时可安全释放

	#停顿期间（stun 动画 0.34s ≈ 20物理帧，取中段 12 帧验证）位置应定格
	for i in 12:
		await get_tree().physics_frame
		if is_instance_valid( ghost2 ) == false or ghost2.state_machine.current_state is ESFlyStunScript == false:
			break
	if is_instance_valid( ghost2 ):
		_check( absf( ghost2.global_position.x - pos2.x ) <= 1.0 , "眩晕期间X轴应保持不变（偏移=%.2f）" % absf( ghost2.global_position.x - pos2.x ) )
		_check( absf( ghost2.global_position.y - pos2.y ) <= 1.0 , "眩晕期间不应下坠（位移=%.2f）" % absf( ghost2.global_position.y - pos2.y ) )

	#眩晕结束后应恢复巡逻（0.34s ≈ 21帧，最多等 90 帧）
	var recovered := false
	for i in 90:
		await get_tree().physics_frame
		if is_instance_valid( ghost2 ) == false:
			break
		if ghost2.state_machine.current_state is ESFly:
			recovered = true
			break
	_check( recovered , "眩晕结束后应恢复 ESFly 巡逻状态" )
	if is_instance_valid( ghost2 ):
		ghost2.queue_free()
	pass
