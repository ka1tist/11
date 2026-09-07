class_name PauseMenu extends CanvasLayer


#region /// 变量
@onready var pause_screen: Control = %PauseScreen
@onready var system: Control = %System

@onready var system_menu_button: Button = %SystemMenuButton

@onready var map_button: Button = %MapButton
@onready var title_button: Button = %TitleButton

@onready var music_slider: HSlider = %MusicSlider
@onready var sfx_slider: HSlider = %SFXSlider
@onready var ui_slider: HSlider = %UISlider
#endregion

var player : Player 
var player_position : Vector2

func _ready() -> void:
	show_pause_screen()
	system_menu_button.pressed.connect( show_system_menu )
	Audio.setup_button_audio( self )
	setup_system_menu()
	player = get_tree().get_first_node_in_group( "Player" ) as Player
	if player:
		player_position = player.global_position
	PlayerHud.show_coin_permanent()
	pass


func _exit_tree() -> void:
	PlayerHud.hide_coin_display()
	pass


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed( "pause" ):
		get_viewport().set_input_as_handled()
		get_tree().paused = false
		queue_free()
	if pause_screen.visible == true:
		if event.is_action_pressed( "ui_cancel" ):
			get_viewport().set_input_as_handled()
			get_tree().paused = false
			queue_free()
		if event.is_action_pressed( "right" ) or event.is_action_pressed( "down" ):
			system_menu_button.grab_focus()
	if system.visible == true:
		#系统设置界面按ui_cancel返回暂停主界面
		if event.is_action_pressed( "ui_cancel" ):
			get_viewport().set_input_as_handled()
			show_pause_screen()
			system_menu_button.grab_focus()
	pass


func show_pause_screen() -> void:
	pause_screen.visible = true
	system.visible = false
	pass 



func show_system_menu() -> void:
	pause_screen.visible = false
	system.visible = true
	map_button.grab_focus()
	pass


func setup_system_menu() -> void:
	music_slider.value = AudioServer.get_bus_volume_linear( 2 )
	sfx_slider.value = AudioServer.get_bus_volume_linear( 3 )
	ui_slider.value = AudioServer.get_bus_volume_linear( 4 )
	
	music_slider.value_changed.connect( _on_music_slider_changed )
	sfx_slider.value_changed.connect( _on_sfx_slider_changed )
	ui_slider.value_changed.connect( _on_ui_slider_changed )
	
	title_button.pressed.connect( _om_back_to_title_perssed )
	map_button.pressed.connect( show_pause_screen )
	pass


func _om_back_to_title_perssed() -> void:
	
	SceneManager.transition_scene( "res://title_screen/title_screen.tscn" , "" , Vector2.ZERO , "up" )
	get_tree().paused = false
	Messages.back_to_title_screen.emit()
	queue_free()
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
