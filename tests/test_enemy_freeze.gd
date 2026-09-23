extends Node2D
## 玩家死亡时敌人冻结测试（headless）：
## 1. hp归零当帧广播 Messages.player_died，且全局只广播一次（重复受伤/重复通知不重发）
## 2. 场景中所有 Enemy（状态机类怪物）立即冻结：物理/AI停止、速度清零、动画暂停、
##    所有伤害判定区关闭、位置不再变化
## 3. 已射出的敌人子弹原地冻结、碰撞检测关闭，不再造成伤害
## 4. 信号不回溯：广播之后新进入场景的敌人（模拟读档重建）保持正常活动
## 运行：Godot_v4.7.1-stable_win64_console.exe --headless --path <项目> res://tests/test_enemy_freeze.tscn

const ENEMY_SCENE := preload( "res://enemies/nature's living dead/nature's living dead.tscn" )
const PLAYER_SCENE := preload( "res://player/player.tscn" )
const BULLET_SCENE := preload( "res://enemies/nature's living dead/bullet.tscn" )
#headless下用preload拿脚本资源构造伤害源，避免全局类缓存差异
const AttackAreaScript := preload( "res://general/scripts/attack_area.gd" )

var _fails : int = 0
var _checks : int = 0
#死亡信号计数（用成员变量：GDScript lambda按值捕获局部变量，改局部副本外层不可见）
var _death_signals : int = 0


func _check( cond : bool , msg : String ) -> void:
	_checks += 1
	if cond == false:
		_fails += 1
		print( "FAIL: " + msg )
pass


func _ready() -> void:
	#========== 准备玩家（入树后会reparent到root） ==========
	var player = PLAYER_SCENE.instantiate()
	add_child( player )
	for i in 3:
		await get_tree().physics_frame

	#========== 准备一个活动中的敌人（已聚焦玩家，处于追击/攻击AI链路中） ==========
	var enemy = ENEMY_SCENE.instantiate()
	var sensor = enemy.find_children( "*" , "PlayerSensor" , true , false )
	if sensor.size() > 0:
		sensor[ 0 ].use_audio_sensor = false
	add_child( enemy )
	enemy.global_position = Vector2( 0 , 0 )
	enemy.affected_by_gravity = false  #测试环境无地面
	enemy.decision_engine._focused = true
	enemy.blackboard.target = player
	player.global_position = Vector2( 200 , 0 )
	for i in 10:
		await get_tree().physics_frame
		enemy.global_position = Vector2( 0 , 0 )
		player.global_position = Vector2( 200 , 0 )
	_check( enemy.is_physics_processing() , "冻结前敌人应处于物理活动状态" )

	#========== 准备一颗飞行中的子弹 ==========
	var bullet = BULLET_SCENE.instantiate()
	add_child( bullet )
	bullet.setup( 1.0 , 1.0 , 250.0 )
	for i in 2:
		await get_tree().physics_frame
	_check( bullet.is_physics_processing() , "冻结前子弹应处于物理飞行状态" )
	_check( bullet.monitoring , "冻结前子弹应开启碰撞检测" )

	#========== 玩家受致命伤死亡（近战/子弹/地刺均走此链路） ==========
	Messages.player_died.connect( _on_player_died_signal )

	var src = AttackAreaScript.new()
	src.damege = 10  #等同地刺一击致命
	player.damage_area.take_damage( src )
	_check( player.hp <= 0 , "致命伤害后hp应为0，实际=%s" % str( player.hp ) )
	_check( player._is_dead , "致命伤害后玩家应标记为已死亡" )
	_check( _death_signals == 1 , "hp归零当帧应广播一次player_died（实际%d次）" % _death_signals )

	#========== 敌人冻结断言（信号同步派发，当帧即生效） ==========
	_check( enemy.frozen , "敌人应进入frozen状态" )
	_check( enemy.is_physics_processing() == false , "敌人物理处理应被关闭（AI/移动/寻路全停）" )
	_check( enemy.velocity == Vector2.ZERO , "敌人速度应清零，实际=%s" % str( enemy.velocity ) )
	_check( enemy.animation.is_playing() == false , "敌人动画应暂停在死亡瞬间的帧" )
	#monitoring为延迟设置（死亡信号可能在物理信号回调中派发），轮询等deferred生效
	var hazard_off := false
	var all_areas_off : bool = false
	for i in 10:
		await get_tree().physics_frame
		hazard_off = enemy.hazard_area.monitoring == false
		all_areas_off = true
		for c in enemy.find_children( "*" ):
			if c is AttackAreaScript and c.monitoring:
				all_areas_off = false
		if hazard_off and all_areas_off:
			break
	_check( hazard_off , "敌人接触伤害区(HazardArea)应关闭" )
	_check( all_areas_off , "敌人所有AttackArea（近战判定/接触伤害）应全部关闭" )

	#再跑10物理帧：位置与速度必须保持冻结（敌人已关物理且无重力，不存在外力）
	var frozen_pos : Vector2 = enemy.global_position
	for i in 10:
		await get_tree().physics_frame
	_check( enemy.global_position == frozen_pos , "冻结后敌人不得自行移动（%s → %s）" % [ str( frozen_pos ) , str( enemy.global_position ) ] )
	_check( enemy.velocity == Vector2.ZERO , "冻结后敌人速度应持续保持为0" )
	_check( enemy.frozen , "持续多帧后敌人仍应处于frozen状态" )

	#========== 子弹冻结断言 ==========
	var bullet_frozen_pos : Vector2 = bullet.global_position
	_check( bullet.is_physics_processing() == false , "子弹物理处理应被关闭（停止飞行）" )
	#monitoring为延迟设置，轮询等待生效
	var bullet_mon_off := false
	for i in 10:
		await get_tree().physics_frame
		if bullet.monitoring == false:
			bullet_mon_off = true
			break
	_check( bullet_mon_off , "子弹碰撞检测应关闭（不再命中玩家）" )
	for i in 5:
		await get_tree().physics_frame
	_check( bullet.global_position.x == bullet_frozen_pos.x , "冻结后子弹应悬停在原位（%.2f → %.2f）" % [ bullet_frozen_pos.x , bullet.global_position.x ] )

	#========== 死亡信号一次性：死后重复受伤/重复通知均不重发 ==========
	player.damage_area.take_damage( src )
	player.notify_death()
	for i in 2:
		await get_tree().physics_frame
	_check( _death_signals == 1 , "player_died全局只应广播一次（实际%d次）" % _death_signals )

	#========== 信号不回溯：广播后新场景敌人（模拟读档重建）保持活动 ==========
	var enemy2 = ENEMY_SCENE.instantiate()
	var sensor2 = enemy2.find_children( "*" , "PlayerSensor" , true , false )
	if sensor2.size() > 0:
		sensor2[ 0 ].use_audio_sensor = false
	add_child( enemy2 )
	enemy2.affected_by_gravity = false
	for i in 5:
		await get_tree().physics_frame
	_check( enemy2.frozen == false , "广播之后新进入场景的敌人不应被追溯冻结" )
	_check( enemy2.is_physics_processing() , "读档重建的敌人应保持正常物理/AI活动" )

	if _fails == 0:
		print( "ENEMY_FREEZE_OK (%d checks)" % _checks )
	else:
		print( "ENEMY_FREEZE_FAILED: %d/%d" % [ _fails , _checks ] )
	get_tree().quit( 1 if _fails > 0 else 0 )
pass


func _on_player_died_signal() -> void:
	_death_signals += 1
pass
