extends CanvasLayer


#region /// on ready variables
@onready var main_menu: VBoxContainer = %MainMenu
@onready var new_main_menu: VBoxContainer = %NewMainMenu
@onready var load_main_menu: VBoxContainer = %LoadMainMenu
@onready var setting_menu: VBoxContainer = %SettingMenu
@onready var setting_music_menu: VBoxContainer = %SettingMusicMenu
@onready var setting_key_menu: VBoxContainer = %SettingKeyMenu


@onready var 开始: Button = %开始
@onready var 加载: Button = %加载
@onready var 设置: Button = %设置
@onready var 结束: Button = %结束


@onready var 存档1: Button = %存档1
@onready var 存档2: Button = %存档2
@onready var 存档3: Button = %存档3

@onready var 加载存档1: Button = %加载存档1
@onready var 加载存档2: Button = %加载存档2
@onready var 加载存档3: Button = %加载存档3

@onready var 声音设置: Button = %声音设置
@onready var 键位设置: Button = %键位设置

@onready var animation_player: AnimationPlayer = $Control/MainMenu/Logo/AnimationPlayer

@onready var music_slider: HSlider = %MusicSlider
@onready var sfx_slider: HSlider = %SFXSlider
@onready var ui_slider: HSlider = %UISlider

@onready var key_grid: GridContainer = %KeyGrid
#endregion

#键位设置界面里每个动作的显示名，顺序与 SaveManager.CONFIG_INPUT_ACTIONS 一致
const KEY_DISPLAY_NAMES : Dictionary = {
	"left" : "向左" ,
	"right" : "向右" ,
	"up" : "向上" ,
	"down" : "向下" ,
	"attack" : "攻击" ,
	"jump" : "跳跃" ,
	"dash" : "冲刺" ,
	"action" : "互动" ,
	"pause" : "暂停" ,
	"health" : "回血" ,
}

#动作名 -> 该行显示/修改键位的按钮
var _key_buttons : Dictionary = {}
#正在等待玩家按键的动作名；空串表示当前没有处于改键状态
var _rebinding : String = ""

var player_position : Vector2

func _ready() -> void:
	开始.pressed.connect( show_new_game_menu )
	加载.pressed.connect( show_load_game_menu )
	设置.pressed.connect( show_setting_menu  )
	结束.pressed.connect( quit_game )
	
	声音设置.pressed.connect( show_setting_music_menu )
	键位设置.pressed.connect( show_setting_key_menu )
	
	
	存档1.pressed.connect( _on_new_game_pressed.bind( 0 ) )
	存档2.pressed.connect( _on_new_game_pressed.bind( 1 ) )
	存档3.pressed.connect( _on_new_game_pressed.bind( 2 ) )
	
	加载存档1.pressed.connect( _on_load_game_presssed.bind( 0 ) )
	加载存档2.pressed.connect( _on_load_game_presssed.bind( 1 ) )
	加载存档3.pressed.connect( _on_load_game_presssed.bind( 2 ) )
	
	#键位行必须在挂按钮音效之前建好：setup_button_audio 只作用于调用时已存在的按钮
	_build_key_rows()
	Audio.setup_button_audio( self )

	#滑条信号只连接一次，重复connect会报错
	music_slider.value_changed.connect( _on_music_slider_changed )
	sfx_slider.value_changed.connect( _on_sfx_slider_changed )
	ui_slider.value_changed.connect( _on_ui_slider_changed )

	show_main_menu()
	#animation_player.animation_finished.connect( _on_animation_finished )
	
	pass
	
	
func _unhandled_input( event: InputEvent ) -> void:
	if not event.is_action_pressed( "ui_cancel" ):
		return
	#逐层返回：键位设置 / 声音设置 -> 设置 -> 主菜单
	if setting_key_menu.visible or setting_music_menu.visible:
		show_setting_menu()
	elif main_menu.visible == false:
		show_main_menu()
	pass


#改键期间吃下所有键盘事件：Esc 取消，其它键写进该动作的绑定。
#放在 _input 阶段（早于按钮的 _gui_input 与 _unhandled_input），标记已处理，
#这样同一次按键不会又触发按钮，也不会顺带触发「返回上一层」
func _input( event: InputEvent ) -> void:
	if _rebinding == "":
		return
	if not ( event is InputEventKey ):
		return
	var key : InputEventKey = event
	if not key.pressed or key.echo:
		return
	get_viewport().set_input_as_handled()
	#两类写法项目里都有：物理键码（方向键）与普通键码（空格/回车/Esc），取非零的那个
	var code : int = key.physical_keycode if key.physical_keycode != 0 else key.keycode
	if code == KEY_ESCAPE:
		_rebinding = ""
		_refresh_key_texts()
		return
	_apply_key_binding( _rebinding , key )
	pass
	

func _hide_all_menus() -> void:
	_rebinding = ""
	main_menu.visible = false
	new_main_menu.visible = false
	load_main_menu.visible = false
	setting_menu.visible = false
	setting_music_menu.visible = false
	setting_key_menu.visible = false
	pass
	

func show_main_menu() -> void:
	_hide_all_menus()
	main_menu.visible = true
	
	开始.grab_focus()
	
	pass

func show_new_game_menu() -> void:
	_hide_all_menus()
	new_main_menu.visible = true
	
	存档1.grab_focus()
	
	if SaveManager.save_file_exists( 0 ):
		存档1.text = " 替 换 存 档 1 "
	
	if SaveManager.save_file_exists( 1 ):
		存档2.text = " 替 换 存 档 2 "
	
	if SaveManager.save_file_exists( 2 ):
		存档3.text = " 替 换 存 档 3 "
	pass

func show_load_game_menu() -> void:
	_hide_all_menus()
	load_main_menu.visible = true
	
	加载存档1.grab_focus()
	
	加载存档1.disabled = not SaveManager.save_file_exists( 0 )
	加载存档2.disabled = not SaveManager.save_file_exists( 1 )
	加载存档3.disabled = not SaveManager.save_file_exists( 2 )
	pass

func show_setting_menu() -> void:
	_hide_all_menus()
	setting_menu.visible = true
	
	声音设置.grab_focus()
	pass

func show_setting_music_menu() -> void:
	_hide_all_menus()
	setting_music_menu.visible = true
	
	music_slider.value = AudioServer.get_bus_volume_linear( 2 )
	sfx_slider.value = AudioServer.get_bus_volume_linear( 3 )
	ui_slider.value = AudioServer.get_bus_volume_linear( 4 )

	music_slider.grab_focus()
	pass

func show_setting_key_menu() -> void:
	_hide_all_menus()
	setting_key_menu.visible = true
	
	_refresh_key_texts()
	for action in _key_buttons:
		var btn := _key_buttons[ action ] as Button
		btn.grab_focus()
		break
	pass


#按 SaveManager.CONFIG_INPUT_ACTIONS 在 KeyGrid 里铺「名称 Label + 按键 Button」的行
func _build_key_rows() -> void:
	for action in SaveManager.CONFIG_INPUT_ACTIONS:
		if not InputMap.has_action( action ):
			continue
		
		var name_label := Label.new()
		name_label.text = KEY_DISPLAY_NAMES.get( action , action )
		name_label.custom_minimum_size = Vector2( 64 , 0 )
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		key_grid.add_child( name_label )
		
		var key_button := Button.new()
		key_button.custom_minimum_size = Vector2( 112 , 26 )
		key_button.add_theme_font_size_override( "font_size" , 14 )
		key_button.pressed.connect( _on_key_button_pressed.bind( action ) )
		key_grid.add_child( key_button )
		
		_key_buttons[ action ] = key_button
	pass


#读取某动作当前的键盘绑定拼成文本（同一动作有多个键时用 / 分隔）
func _key_text( action : String ) -> String:
	var parts : Array[ String ] = []
	for e in InputMap.action_get_events( action ):
		if not ( e is InputEventKey ):
			continue
		var key : InputEventKey = e
		var code : int = key.physical_keycode if key.physical_keycode != 0 else key.keycode
		if code == 0:
			continue
		parts.append( OS.get_keycode_string( code ) )
	if parts.is_empty():
		return "未 绑 定"
	return " / ".join( parts )


func _refresh_key_texts() -> void:
	for action in _key_buttons:
		var btn := _key_buttons[ action ] as Button
		btn.text = _key_text( action )
	pass


func _on_key_button_pressed( action : String ) -> void:
	_rebinding = action
	var btn := _key_buttons[ action ] as Button
	btn.text = "按 任 意 键 …"
	pass


#把新键写进该动作：清掉原有的键盘绑定（保留手柄/摇杆），只留这一个新键。
#InputMap 没有「只删键盘事件」的接口，只能整组清空后再把非键盘的挂回去
func _apply_key_binding( action : String , key : InputEventKey ) -> void:
	var kept : Array[ InputEvent ] = []
	for e in InputMap.action_get_events( action ):
		if not ( e is InputEventKey ):
			kept.append( e )
	InputMap.action_erase_events( action )
	for e in kept:
		InputMap.action_add_event( action , e )
	
	var new_key := InputEventKey.new()
	new_key.physical_keycode = key.physical_keycode
	new_key.keycode = key.keycode
	InputMap.action_add_event( action , new_key )
	#改的是方向键的话，界面导航键同步跟上，否则刚设的键在菜单里没法上下选择按钮
	SaveManager.sync_direction_ui_actions()
	
	_rebinding = ""
	_refresh_key_texts()
	#改键立即落盘到 user://settings.cfg，下次启动由 SaveManager.load_configuration 恢复
	SaveManager.save_configuration()
	pass


func _on_new_game_pressed( slot : int ) -> void:
	SaveManager.create_new_game_save( slot )
	#SceneManager.transition_scene(
	#	"uid://d31trrcaeoqp4" , "" , Vector2.ZERO , "up"
	#)
	pass


func _on_load_game_presssed( slot : int ) -> void:
	SaveManager.load_game( slot )
	pass

func play_spatial_sound( audio : AudioStream , pos : Vector2 ) -> void:
	var ap : AudioStreamPlayer2D = AudioStreamPlayer2D.new()
	add_child( ap )
	ap.bus = "SFX"
	ap.global_position = pos
	ap.stream = audio
	ap.finished.connect( ap.queue_free )
	ap.play()
	pass


func _on_music_slider_changed( v : float ) -> void:
	AudioServer.set_bus_volume_linear( 2 , v )
	SaveManager.save_configuration()
	pass

func _on_sfx_slider_changed( v : float ) -> void:
	AudioServer.set_bus_volume_linear( 3 , v )
	Audio.play_spatial_sound( Audio.ui_focus_audio , player_position )
	SaveManager.save_configuration()
	pass


func _on_ui_slider_changed( v : float ) -> void:
	AudioServer.set_bus_volume_linear( 4 , v )
	Audio.ui_focus_change()
	SaveManager.save_configuration()
	pass

func quit_game() -> void:
	get_tree().quit()
	pass
	
#func _on_animation_finished( anim_name : String ) -> void:
	#if anim_name == "start":
		#animation_player.play( "loop" )
#	pass
