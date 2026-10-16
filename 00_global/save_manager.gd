extends Node

const CONFIG_FILE_PATH = "user://settings.cfg"
const SLOTS : Array[ String ] = [ "save_01","save_02","save_03" ]
const DIAMOND_ITEM := preload( "res://pause_menu/bag/items/diamond.tres" )

var current_slot : int = 0 
var save_data : Dictionary 
var discovered_areas : Array = []
var persistent_data : Dictionary = {}



func _ready() -> void:
	load_configuration()
	SceneManager.scene_entered.connect( _on_scene_entered )
	pass
	


func _unhandled_key_input(event: InputEvent) -> void:
	if OS.is_debug_build():
		if event is InputEventKey and event.pressed:
			if event.keycode == KEY_F5:
				save_game()
			elif event.keycode == KEY_F7:
				load_game( current_slot )
			elif event.keycode == KEY_1:
				current_slot = 0
			elif event.keycode == KEY_2:
				current_slot = 1
			elif event.keycode == KEY_3:
				current_slot = 2
	pass



func create_new_game_save( slot : int ) -> void:
	current_slot = slot
	discovered_areas.clear()
	persistent_data.clear()
	var new_game_scene : String = "uid://d31trrcaeoqp4"
	discovered_areas.append( new_game_scene )
	save_data = {
		"scene_path" : new_game_scene,
		"x" : 80,
		"y" : 288,
		"hp" : 5,
		"max_hp" : 5,
		"dash" : false,
		"double_jump" : false,
		"ground_slam" : false,
		"morph_roll" : false,
		"wall_climb" : false,
		"coin" : 0,
		"diamond" : 0,
		"potion" : Player.POTION_MAX,
		"attack_power_bonus" : 0.0,
		"loot_magnet_range" : Player.LOOT_MAGNET_RANGE_DEFAULT,
		"discovered_areas" : discovered_areas,
		"persistent_data" : persistent_data,
		"inventory" : [],
	}
	var save_file = FileAccess.open( get_file_name( current_slot ) , FileAccess.WRITE )
	save_file.store_line( JSON.stringify( save_data ) )

	save_file.close()
	load_game( slot )
	pass
	
	
func save_game() ->void:
	var player : Player = get_tree().get_first_node_in_group( "Player" )
	if player == null:
		return
	save_data = {
		"scene_path" : SceneManager.current_scene_uid,
		"x" : player.global_position.x,
		"y" : player.global_position.y,
		"hp" : player.hp,
		"max_hp" : player.max_hp,
		"dash" : player.dash,
		"double_jump" : player.double_jump,
		"ground_slam" : player.ground_slam,
		"morph_roll" : player.morph_roll,
		"wall_climb" : player.wall_climb,
		"coin" : player.coin,
		"diamond" : player.diamond,
		"potion" : player.potion,
		"attack_power_bonus" : player.attack_power_bonus,
		"loot_magnet_range" : player.loot_magnet_range,
		"discovered_areas" : discovered_areas,
		"persistent_data" : persistent_data,
		"inventory" : Inventory.serialize(),
	}
	var save_file = FileAccess.open( get_file_name( current_slot ) , FileAccess.WRITE )
	save_file.store_line( JSON.stringify( save_data ) )
	pass


# 保存玩家进度（能力、金币、钻石、最大血量、持久化数据），但保留上一次存档点的场景与位置
# 用于拾取物品/获得能力时自动保存，确保死亡重生后进度不丢失且回到存档点
func save_progress() -> void:
	var player : Player = get_tree().get_first_node_in_group( "Player" )
	if player == null:
		return
	if save_data == null:
		save_data = {}
	save_data[ "hp" ] = player.max_hp
	save_data[ "max_hp" ] = player.max_hp
	save_data[ "dash" ] = player.dash
	save_data[ "double_jump" ] = player.double_jump
	save_data[ "ground_slam" ] = player.ground_slam
	save_data[ "morph_roll" ] = player.morph_roll
	save_data[ "wall_climb" ] = player.wall_climb
	save_data[ "coin" ] = player.coin
	save_data[ "diamond" ] = player.diamond
	save_data[ "potion" ] = player.potion
	save_data[ "attack_power_bonus" ] = player.attack_power_bonus
	save_data[ "loot_magnet_range" ] = player.loot_magnet_range
	save_data[ "persistent_data" ] = persistent_data
	save_data[ "inventory" ] = Inventory.serialize()
	# 不更新 scene_path / x / y：保留上一次存档点的位置
	var save_file = FileAccess.open( get_file_name( current_slot ) , FileAccess.WRITE )
	save_file.store_line( JSON.stringify( save_data ) )
	pass
	
	
func load_game( slot : int ) -> void:
	if not FileAccess.file_exists( get_file_name( current_slot ) ):
		return
	current_slot = slot
		
	var save_file = FileAccess.open( get_file_name( current_slot ), FileAccess.READ )
	save_data = JSON.parse_string( save_file.get_line() )
	#合并而非替换：破坏过的墙体记录不因读档回档而丢失，新游戏时才重置
	var loaded_persistent : Dictionary = save_data.get( "persistent_data" , {} )
	for key in loaded_persistent:
		persistent_data[ key ] = loaded_persistent[ key ]
	#恢复背包（旧版本存档无此字段时回退默认物品）
	Inventory.deserialize( save_data.get( "inventory" , [] ) )
	discovered_areas = save_data.get( "discovered_areas" , [] )
	var scene_path : String = save_data.get( "scene_path" , "uid://d31trrcaeoqp4" )
	SceneManager.transition_scene( scene_path , "" , Vector2.ZERO , "up" )
	await SceneManager.new_scene_ready
	setup_player()
	pass



func setup_player() -> void:
	var player : Player = null
	while not player:
		player = get_tree().get_first_node_in_group( "Player" )
		await get_tree().process_frame
	
	player.max_hp = save_data.get( "max_hp" , 5 )
	player.hp = save_data.get( "hp" , 5 )
	
	player.dash = save_data.get( "dash" , false )
	player.double_jump = save_data.get( "double_jump" , false )
	player.ground_slam = save_data.get( "ground_slam" , false )
	player.morph_roll = save_data.get( "morph_roll" , false )
	player.wall_climb = save_data.get( "wall_climb" , false )
	player.coin = save_data.get( "coin" , 0 )
	player.diamond = save_data.get( "diamond" , 0 )
	# 兼容旧存档：血瓶系统上线前无此字段时，按初始值补满（初始即为上限）
	player.potion = save_data.get( "potion" , Player.POTION_MAX )
	# 兼容旧存档：强化系统上线前无此字段时回退 0 加成
	player.set_attack_power_bonus( save_data.get( "attack_power_bonus" , 0.0 ) )
	# 兼容旧存档：磁铁道具上线前无此字段时回退默认磁吸范围
	player.loot_magnet_range = save_data.get( "loot_magnet_range" , Player.LOOT_MAGNET_RANGE_DEFAULT )
	# 兼容旧存档：背包系统上线前已拾取的钻石补入背包（钻石只增不减，以计数为准单向同步）
	var diamond_in_bag : int = Inventory.get_item_amount( &"diamond" )
	if player.diamond > diamond_in_bag:
		Inventory.add_item( DIAMOND_ITEM , player.diamond - diamond_in_bag )

	player.global_position = Vector2( save_data.get( "x" , 0 ) , save_data.get( "y" , 0 ) )
	#落位完成后广播：按位置决定自身状态的场景元素据此校正（典型是村庄的房子——
	#存档存的是玩家站在存档点上的坐标，而房屋每次进场景都是「屋外」外观、
	#内景地面碰撞关闭，不校正会让玩家站在内景坐标上却穿过地板掉到屋外）
	Messages.player_spawned.emit()
	pass


func get_file_name( slot : int ) -> String:
	return "user://" + SLOTS[ slot ] + ".sav"


func save_file_exists( _slot : int ) -> bool:
	return FileAccess.file_exists( get_file_name( current_slot ) )
	


func is_area_discoverd( scene_uid : String ) -> bool:
	return discovered_areas.has( scene_uid )


func _on_scene_entered( scene_uid : String ) -> void:
	if discovered_areas.has( scene_uid ):
		return
	else:
		discovered_areas.append( scene_uid )
	pass


#region /// configuration settings

func save_configuration() -> void:
	var config := ConfigFile.new()
	config.set_value( "audio" , "music" , AudioServer.get_bus_volume_linear( 2 ) )
	config.set_value( "audio" , "sfx" , AudioServer.get_bus_volume_linear( 3 ) )
	config.set_value( "audio" , "ui" , AudioServer.get_bus_volume_linear( 4 ) )
	config.save( CONFIG_FILE_PATH )
	pass

func load_configuration() -> void:
	var config := ConfigFile.new()
	var err = config.load( CONFIG_FILE_PATH )
	
	if err != OK:
		AudioServer.set_bus_volume_linear( 2 , 0.8 )
		AudioServer.set_bus_volume_linear( 3 , 1.0 ) 
		AudioServer.set_bus_volume_linear( 4 ,  1.0 )
		save_configuration()
		return
		
	AudioServer.set_bus_volume_linear( 2 , config.get_value( "audio" , "music" , 0.8 ) )
	AudioServer.set_bus_volume_linear( 3 , config.get_value( "audio" , "sfx" , 1.0 ) )
	AudioServer.set_bus_volume_linear( 4 , config.get_value( "audio" , "ui" , 1.0 ) )
	pass
#endregion
