extends CanvasLayer


#region /// on ready variables
@onready var main_menu: VBoxContainer = %MainMenu
@onready var new_main_menu: VBoxContainer = %NewMainMenu
@onready var load_main_menu: VBoxContainer = %LoadMainMenu
@onready var setting_menu: VBoxContainer = %SettingMenu



@onready var 开始: Button = %开始
@onready var 加载: Button = %加载
@onready var 设置: Button = %设置

@onready var 存档1: Button = %存档1
@onready var 存档2: Button = %存档2
@onready var 存档3: Button = %存档3

@onready var 加载存档1: Button = %加载存档1
@onready var 加载存档2: Button = %加载存档2
@onready var 加载存档3: Button = %加载存档3

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
	
	存档1.pressed.connect( _on_new_game_pressed.bind( 0 ) )
	存档2.pressed.connect( _on_new_game_pressed.bind( 1 ) )
	存档3.pressed.connect( _on_new_game_pressed.bind( 2 ) )
	
	加载存档1.pressed.connect( _on_load_game_presssed.bind( 0 ) )
	加载存档2.pressed.connect( _on_load_game_presssed.bind( 1 ) )
	加载存档3.pressed.connect( _on_load_game_presssed.bind( 2 ) )
	
	Audio.setup_button_audio( self )
	
	show_main_menu()
	#animation_player.animation_finished.connect( _on_animation_finished )
	
	pass
	
	
func _unhandled_input( event: InputEvent ) -> void:
	if event.is_action_pressed( "ui_cancel" ):
		if main_menu.visible == false:
			
			show_main_menu()
	pass
	

func show_main_menu() -> void:
	main_menu.visible = true
	new_main_menu.visible = false
	load_main_menu.visible = false
	setting_menu.visible = false
	
	开始.grab_focus()
	
	pass

func show_new_game_menu() -> void:
	main_menu.visible = false
	new_main_menu.visible = true
	load_main_menu.visible = false
	setting_menu.visible = false
	
	存档1.grab_focus()
	
	if SaveManager.save_file_exists( 0 ):
		存档1.text = " 替 换 存 档 1 "
	
	if SaveManager.save_file_exists( 1 ):
		存档2.text = " 替 换 存 档 2 "
	
	if SaveManager.save_file_exists( 0 ):
		存档3.text = " 替 换 存 档 3 "
	pass

func show_load_game_menu() -> void:
	main_menu.visible = false
	new_main_menu.visible = false
	load_main_menu.visible = true
	setting_menu.visible = false
	
	加载存档1.grab_focus()
	
	加载存档1.disabled = not SaveManager.save_file_exists( 0 )
	加载存档2.disabled = not SaveManager.save_file_exists( 1 )
	加载存档3.disabled = not SaveManager.save_file_exists( 2 )
	pass

func show_setting_menu() -> void:
	main_menu.visible = false
	new_main_menu.visible = false
	load_main_menu.visible = false
	setting_menu.visible = true
	
	music_slider.value = AudioServer.get_bus_volume_linear( 2 )
	sfx_slider.value = AudioServer.get_bus_volume_linear( 3 )
	ui_slider.value = AudioServer.get_bus_volume_linear( 4 )
	
	music_slider.value_changed.connect( _on_music_slider_changed )
	sfx_slider.value_changed.connect( _on_sfx_slider_changed )
	ui_slider.value_changed.connect( _on_ui_slider_changed )
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
#func _on_animation_finished( anim_name : String ) -> void:
	#if anim_name == "start":
		#animation_player.play( "loop" )
#	pass
