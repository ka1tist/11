extends CanvasLayer


@onready var hp_margin_container: MarginContainer = %HPMarginContainer
@onready var hp_bar: TextureProgressBar = %HPBar

@onready var game_over: Control = %GameOver

@onready var quit_button: Button = %QuitButton
@onready var load_button: Button = %LoadButton

@onready var coin_container: HBoxContainer = %CoinContainer
@onready var coin_label: Label = %CoinLabel

@onready var up_container: HBoxContainer = %UpContainer
@onready var up_label: Label = %UpLabel

var coin_tween: Tween
var up_tween: Tween


func _ready() -> void:
	Messages.player_health_changed.connect( update_health_bar )
	Messages.coin_collected.connect( _on_coin_collected )
	Messages.diamond_collected.connect( _on_diamond_collected )
	game_over.visible = false
	up_container.visible = false
	load_button.pressed.connect( _on_load_pressed )
	quit_button.pressed.connect( _on_quit_pressed )
	pass
	
	
	
func update_health_bar( hp : float , max_hp : float ) -> void:
	var value : float = ( hp / max_hp ) * 100
	hp_bar.value = value
	hp_margin_container.size.x = max_hp + 22
	pass


func _on_coin_collected( coin : int ) -> void:
	coin_label.text = str( coin )
	if coin_tween:
		coin_tween.kill()
	coin_container.modulate.a = 0
	coin_container.visible = true
	#淡入0.2s → 保持0.6s → 淡出0.2s，总计1秒
	coin_tween = create_tween()
	coin_tween.tween_property( coin_container , "modulate:a" , 1.0 , 0.2 )
	coin_tween.tween_interval( 0.6 )
	coin_tween.tween_property( coin_container , "modulate:a" , 0.0 , 0.2 )
	coin_tween.finished.connect( func(): coin_container.visible = false )
	pass


#暂停菜单打开时永久显示金币计数
func show_coin_permanent() -> void:
	if coin_tween:
		coin_tween.kill()
	var player : Player = get_tree().get_first_node_in_group( "Player" )
	if player:
		coin_label.text = str( player.coin )
	coin_container.modulate.a = 1.0
	coin_container.visible = true
	pass


#暂停菜单关闭时恢复默认隐藏
func hide_coin_display() -> void:
	if coin_tween:
		coin_tween.kill()
	coin_container.modulate.a = 0.0
	coin_container.visible = false
	pass


func _on_diamond_collected( diamond : int ) -> void:
	up_label.text = str( diamond )
	if up_tween:
		up_tween.kill()
	up_container.modulate.a = 0
	up_container.visible = true
	#淡入0.2s → 保持0.6s → 淡出0.2s，总计1秒（与CoinContainer动画一致）
	up_tween = create_tween()
	up_tween.tween_property( up_container , "modulate:a" , 1.0 , 0.2 )
	up_tween.tween_interval( 0.6 )
	up_tween.tween_property( up_container , "modulate:a" , 0.0 , 0.2 )
	up_tween.finished.connect( func(): up_container.visible = false )
	pass


#暂停菜单打开时永久显示钻石计数
func show_up_permanent() -> void:
	if up_tween:
		up_tween.kill()
	var player : Player = get_tree().get_first_node_in_group( "Player" )
	if player:
		up_label.text = str( player.diamond )
	up_container.modulate.a = 1.0
	up_container.visible = true
	pass


#暂停菜单关闭时恢复默认隐藏
func hide_up_display() -> void:
	if up_tween:
		up_tween.kill()
	up_container.modulate.a = 0.0
	up_container.visible = false
	pass


func show_game_over() ->void:
	load_button.visible = false
	quit_button.visible = false
	
	game_over.modulate.a = 0
	game_over.visible = true
	
	var tween : Tween = create_tween()
	tween.tween_property( game_over , "modulate" , Color.WHITE , 2.0 )
	await tween.finished
	
	load_button.visible = true
	quit_button.visible = true
	
	load_button.grab_focus()
	pass



func clear_game_over() ->void:
	load_button.visible = false
	quit_button.visible = false
	await SceneManager.scene_entered
	game_over.visible = false
	var player : Player = get_tree().get_first_node_in_group( "Player" )
	player.queue_free()
	pass



func _on_load_pressed() -> void:
	SaveManager.load_game( SaveManager.current_slot )
	clear_game_over()
	pass


func _on_quit_pressed() -> void:
	SceneManager.transition_scene( "res://title_screen/title_screen.tscn" , "" , Vector2.ZERO , "up" )
	clear_game_over()
	pass
