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


func _ready() -> void:
	show_pause_screen()
	system_menu_button.pressed.connect( show_system_menu )
	setup_system_menu()
	pass


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed( "pause" ):
		get_viewport().set_input_as_handled()
		get_tree().paused = false
		queue_free()
	if pause_screen.visible == true:
		if event.is_action_pressed( "right" ) or event.is_action_pressed( "down" ):
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
	title_button.pressed.connect( _om_back_to_title_perssed )
	map_button.pressed.connect( show_pause_screen )
	pass


func _om_back_to_title_perssed() -> void:
	
	SceneManager.transition_scene( "res://title_screen/title_screen.tscn" , "" , Vector2.ZERO , "up" )
	get_tree().paused = false
	Messages.back_to_title_screen.emit()
	queue_free()
	pass
