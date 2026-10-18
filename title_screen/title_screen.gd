extends CanvasLayer


#region /// on ready variables
@onready var main_menu: VBoxContainer = %MainMenu
@onready var new_main_menu: VBoxContainer = %NewMainMenu
@onready var load_main_menu: VBoxContainer = %LoadMainMenu
@onready var setting_menu: VBoxContainer = %SettingMenu
@onready var setting_music_menu: VBoxContainer = %SettingMusicMenu
@onready var setting_key_menu: KeyBindMenu = %SettingKeyMenu


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
#endregion

var player_position : Vector2

func _ready() -> void:
	开始.pressed.connect( show_new_game_menu )
	加载.pressed.connect( show_load_game_menu )
	设置.pressed.connect( show_setting_menu  )
	结束.pressed.connect( quit_game )
	
	声音设置.pressed.connect( show_setting_music_menu )
	键位设置.pressed.connect( show_setting_key_menu )
	#键位面板自己的 Esc 处理：改键中只取消改键，其余情况发信号回到设置菜单
	setting_key_menu.back_requested.connect( show_setting_menu )
	
	
	存档1.pressed.connect( _on_new_game_pressed.bind( 0 ) )
	存档2.pressed.connect( _on_new_game_pressed.bind( 1 ) )
	存档3.pressed.connect( _on_new_game_pressed.bind( 2 ) )
	
	加载存档1.pressed.connect( _on_load_game_presssed.bind( 0 ) )
	加载存档2.pressed.connect( _on_load_game_presssed.bind( 1 ) )
	加载存档3.pressed.connect( _on_load_game_presssed.bind( 2 ) )
	
	#键位行的按钮由 KeyBindMenu 自己在 _ready 里铺（子节点 _ready 早于本节点），
	#所以这里挂音效时它们已经存在
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
	#逐层返回：声音设置 -> 设置 -> 主菜单。
	#键位设置这一层由 KeyBindMenu 自己处理（改键中只取消改键），所以这里不判它
	if setting_music_menu.visible:
		show_setting_menu()
	elif main_menu.visible == false:
		show_main_menu()
	pass


func _hide_all_menus() -> void:
	#顺手丢掉键位面板里未完成的改键状态
	setting_key_menu.close()
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
	#刷新键位文字并把焦点放到第一行
	setting_key_menu.open()
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
