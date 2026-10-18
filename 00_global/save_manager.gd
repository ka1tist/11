extends Node

const CONFIG_FILE_PATH = "user://settings.cfg"
const SLOTS : Array[ String ] = [ "save_01","save_02","save_03" ]
#参与配置保存/恢复的键位动作：与 title_screen 的键位设置菜单里展示的一一对应（顺序即界面行序）。
#不含 ui_accept / ui_cancel：那是引擎内置的界面导航键，不开放给玩家改
const CONFIG_INPUT_ACTIONS : Array[ String ] = [ "left" , "right" , "up" , "down" , "attack" , "jump" , "dash" , "action" , "pause" , "health" ]
#移动动作 -> 界面导航动作。标题界面（主菜单/设置/键位）的焦点移动用的是引擎内置的
#ui_left/ui_right/ui_up/ui_down，和本游戏的移动动作是两套独立映射；不同步的话，
#玩家把「向上」改到别的键之后，在标题界面里按新键就没反应（而暂停菜单/背包/商店用的是移动动作，会正常跟随）
const DIRECTION_UI_ACTIONS : Dictionary = {
	"left" : "ui_left" ,
	"right" : "ui_right" ,
	"up" : "ui_up" ,
	"down" : "ui_down" ,
}
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
	if not FileAccess.file_exists( get_file_name( slot ) ):
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


func save_file_exists( slot : int ) -> bool:
	return FileAccess.file_exists( get_file_name( slot ) )
	


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
	#键位：按动作保存当前的全部键盘绑定（手柄/摇杆绑定不落盘，始终用 project.godot 的默认值）
	var keys : Dictionary = {}
	for action in CONFIG_INPUT_ACTIONS:
		if not InputMap.has_action( action ):
			continue
		var list : Array = []
		for e in InputMap.action_get_events( action ):
			if e is InputEventKey:
				var k : InputEventKey = e
				list.append( {
					"physical_keycode" : k.physical_keycode ,
					"keycode" : k.keycode ,
				} )
		if not list.is_empty():
			keys[ action ] = list
	config.set_value( "input" , "keys" , keys )
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
	#键位：把配置里存的键盘绑定写回 InputMap（没有配置时这里拿到空字典，等于不动作）
	_apply_saved_input( config.get_value( "input" , "keys" , {} ) )
	#改过方向键的话，界面导航键也要跟着走，否则标题界面里按新方向键没反应
	sync_direction_ui_actions()
	pass


#把配置里保存的键位写回 InputMap：只动键盘绑定（InputEventKey），
#手柄按键/摇杆绑定原样保留。InputMap 没有「只删键盘键」的接口，所以整组清空后再把非键盘的挂回去
func _apply_saved_input( saved : Dictionary ) -> void:
	for action in saved:
		if not InputMap.has_action( action ):
			continue
		var kept : Array[ InputEvent ] = []
		for e in InputMap.action_get_events( action ):
			if not ( e is InputEventKey ):
				kept.append( e )
		InputMap.action_erase_events( action )
		for e in kept:
			InputMap.action_add_event( action , e )
		for entry in saved[ action ]:
			#keycode 一类属性是枚举类型（Key），int 赋值要显式转过去
			var key := InputEventKey.new()
			key.physical_keycode = int( entry.get( "physical_keycode" , 0 ) ) as Key
			key.keycode = int( entry.get( "keycode" , 0 ) ) as Key
			InputMap.action_add_event( action , key )
	pass


#把方向动作当前的键盘绑定同步进 ui_left/ui_right/ui_up/ui_down，让标题界面的菜单
#跟着玩家自己的方向键走。规则与游戏动作一致：只替换键盘绑定，手柄/摇杆（十字键）原样保留。
#方向键的引擎默认值与移动键默认值本来就是同一组方向键，所以没改过键位的玩家行为不变
func sync_direction_ui_actions() -> void:
	for action in DIRECTION_UI_ACTIONS:
		var ui_action : String = DIRECTION_UI_ACTIONS[ action ]
		if not InputMap.has_action( action ) or not InputMap.has_action( ui_action ):
			continue
		var kept : Array[ InputEvent ] = []
		for e in InputMap.action_get_events( ui_action ):
			if not ( e is InputEventKey ):
				kept.append( e )
		InputMap.action_erase_events( ui_action )
		for e in kept:
			InputMap.action_add_event( ui_action , e )
		for e in InputMap.action_get_events( action ):
			if e is InputEventKey:
				InputMap.action_add_event( ui_action , e )
	pass


#把键位恢复成 project.godot 的出厂默认（键盘与手柄绑定一并还原）。
#改键只动运行时的 InputMap，ProjectSettings 里的 input/<action> 自始至终没被改过，
#所以直接读它拿到的就是默认值；按键 / 手柄 / 摇杆事件原样挂回，忽略其中序列化出的空槽
func restore_default_input() -> void:
	for action in CONFIG_INPUT_ACTIONS:
		if not InputMap.has_action( action ):
			continue
		var defaults : Dictionary = ProjectSettings.get_setting( "input/" + action , {} )
		var events : Array = defaults.get( "events" , [] )
		if events.is_empty():
			continue
		InputMap.action_erase_events( action )
		for e in events:
			if e is InputEvent:
				InputMap.action_add_event( action , e )
	#方向键回到默认后，界面导航键要重新对齐
	sync_direction_ui_actions()
	pass
#endregion
