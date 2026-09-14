extends Node2D
## nature's living dead 近程/远程双模攻击测试（headless）：
## 1. 玩家在50单位外：播 attack_2，动画0.5秒时从(0,-24)发射子弹，子弹沿X轴匀速直线飞行
## 2. 玩家在50单位内：播 attack 近程攻击，不生成子弹
## 3. 子弹命中玩家造成可配置伤害
## 4. 未发现玩家时不攻击（保持巡逻）
## 运行：Godot_v4.7.1-stable_win64_console.exe --headless --path <项目> res://tests/test_ranged_attack.tscn

const ENEMY_SCENE := preload( "res://enemies/nature's living dead/nature's living dead.tscn" )
const PLAYER_SCENE := preload( "res://player/player.tscn" )
const ESRangedAttackScript := preload( "res://enemies/scripts/states/es_ranged_attack.gd" )
const BULLET_SCRIPT_PATH := "res://enemies/nature's living dead/bullet.gd"

var _fails : int = 0
var _checks : int = 0


func _check( cond : bool , msg : String ) -> void:
	_checks += 1
	if cond == false:
		_fails += 1
		print( "FAIL: " + msg )
	pass


func _find_bullets() -> Array:
	var out : Array = []
	for c in get_children():
		if c is Area2D and c.get_script() and c.get_script().resource_path == BULLET_SCRIPT_PATH:
			out.append( c )
	return out


func _ready() -> void:
	#========== 场景1：远程攻击 ==========
	var enemy = ENEMY_SCENE.instantiate()
	#入树前关闭音频感知（_ready 会按该值决定是否连接声音信号），只保留视觉传感器路径
	var sensor = enemy.find_children( "*" , "PlayerSensor" , true , false )
	if sensor.size() > 0:
		sensor[0].use_audio_sensor = false
	add_child( enemy )
	enemy.global_position = Vector2( 0 , 0 )
	enemy.affected_by_gravity = false  #测试环境无地面，关闭重力保持位置稳定
	var player = PLAYER_SCENE.instantiate()
	player.position = Vector2( 600 , 0 )  #入树前定位，避免Area2D对入树首帧默认位置(0,0)的滞后误报
	add_child( player )  #初始在 PlayerSensor 视锥(240px)外
	for i in 5:
		await get_tree().physics_frame
		player.global_position = Vector2( 600 , 0 )
	_check( enemy.state_machine.current_state is ESWalk , "未发现玩家时应保持巡逻" )

	#跳过 focus 聚焦阶段，直接进入战斗判定；瞬移玩家到150（距离150 > 50 → 远程）
	enemy.decision_engine._focused = true
	enemy.blackboard.target = player
	player.global_position = Vector2( 150 , 0 )
	for i in 5:
		await get_tree().physics_frame
		player.global_position = Vector2( 150 , 0 )
		enemy.global_position = Vector2( 0 , 0 )
	var atk = enemy.state_machine.current_state
	_check( atk is ESRangedAttackScript , "距离>50应进入双模攻击状态" )
	_check( atk._is_ranged == true , "距离>50应选择远程模式(_is_ranged)" )
	_check( enemy.animation.current_animation == "attack_2" , "远程模式应播放 attack_2 动画" )
	_check( _find_bullets().is_empty() , "0.5秒前不应有子弹" )

	#0.5秒前（约20物理帧≈0.33s）确认仍无子弹
	for i in 18:
		await get_tree().physics_frame
		player.global_position = Vector2( 150 , 0 )
		enemy.global_position = Vector2( 0 , 0 )
	_check( _find_bullets().is_empty() , "动画未到0.5秒不应提前发射子弹" )

	#等到0.5秒后子弹出现
	var bullet = null
	for i in 20:
		await get_tree().physics_frame
		player.global_position = Vector2( 150 , 0 )
		enemy.global_position = Vector2( 0 , 0 )
		var bs = _find_bullets()
		if bs.size() > 0:
			bullet = bs[0]
			break
	_check( bullet != null , "attack_2 动画到0.5秒时应生成子弹" )

	if bullet:
		#发射点应为敌人局部(0,-24)的世界坐标
		var spawn_ok := absf( bullet.global_position.x - 0.0 ) <= 3.0 and absf( bullet.global_position.y - ( -24.0 ) ) <= 3.0
		_check( spawn_ok , "子弹应从(0,-24)位置发射，实际=%s" % str( bullet.global_position ) )
		#匀速直线：相邻采样点 dx≈speed*dt，dy=0
		var p1 : Vector2 = bullet.global_position
		await get_tree().physics_frame
		await get_tree().physics_frame
		var p2 : Vector2 = bullet.global_position
		var dx : float = p2.x - p1.x
		var dy : float = p2.y - p1.y
		var expect : float = atk.bullet_speed * 2.0 / 60.0
		_check( absf( dx - expect ) <= 2.0 , "子弹应沿X轴匀速飞行(期望位移%.1f，实际%.1f)" % [ expect , dx ] )
		_check( absf( dy ) <= 0.5 , "子弹Y轴应保持不变（实际dy=%.2f）" % dy )
		_check( dx > 0 , "玩家在右侧时子弹应向右飞" )
		_check( absf( bullet.damege - atk.bullet_damage ) < 0.001 , "子弹伤害应等于配置值" )

	#子弹继续飞行命中玩家（150px，约0.6s命中），玩家扣血
	var hp_before : int = player.hp
	var hit_ok := false
	for i in 90:
		await get_tree().physics_frame
		player.global_position = Vector2( 150 , 0 )
		enemy.global_position = Vector2( 0 , 0 )
		if player.hp < hp_before:
			hit_ok = true
			break
	_check( hit_ok , "子弹命中玩家应造成伤害（hp %d → %d）" % [ hp_before , player.hp ] )
	await get_tree().physics_frame  #queue_free 为帧末延迟释放，等一帧再确认销毁
	_check( _find_bullets().is_empty() , "子弹命中后应销毁" )

	#清理场景1的敌人，防止其冷却结束后再次发射干扰场景2的断言
	enemy.blackboard.target = null
	enemy.queue_free()
	await get_tree().physics_frame

	#========== 场景2：近程攻击（距离<=50）==========
	var enemy2 = ENEMY_SCENE.instantiate()
	var sensor2 = enemy2.find_children( "*" , "PlayerSensor" , true , false )
	if sensor2.size() > 0:
		sensor2[0].use_audio_sensor = false
	add_child( enemy2 )
	enemy2.global_position = Vector2( -400 , 0 )
	enemy2.affected_by_gravity = false
	enemy2.blackboard.target = null
	enemy2.decision_engine._focused = true
	player.global_position = Vector2( -360 , 0 )  #距离40 <= 50 → 近程
	enemy2.blackboard.target = player
	for i in 8:
		await get_tree().physics_frame
		player.global_position = Vector2( -360 , 0 )
		enemy2.global_position = Vector2( -400 , 0 )
	var atk2 = enemy2.state_machine.current_state
	_check( atk2 is ESRangedAttackScript , "距离<=50也应进入双模攻击状态" )
	_check( atk2._is_ranged == false , "距离<=50应选择近程模式" )
	_check( enemy2.animation.current_animation == "attack" , "近程模式应播放 attack 动画" )
	#整个近程攻击动画期间（1.0s≈60帧）不应生成子弹
	for i in 60:
		await get_tree().physics_frame
		player.global_position = Vector2( -360 , 0 )
		enemy2.global_position = Vector2( -400 , 0 )
	_check( _find_bullets().is_empty() , "近程攻击期间不应生成子弹" )

	if _fails == 0:
		print( "RANGED_ATTACK_OK (%d checks)" % _checks )
	else:
		print( "RANGED_ATTACK_FAILED: %d/%d" % [ _fails , _checks ] )
	get_tree().quit( 1 if _fails > 0 else 0 )
	pass
