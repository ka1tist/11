extends CanvasLayer


@onready var hp_margin_container: MarginContainer = %HPMarginContainer
@onready var hp_container: HBoxContainer = %HPContainer

@onready var game_over: Control = %GameOver

@onready var quit_button: Button = %QuitButton
@onready var load_button: Button = %LoadButton

@onready var coin_container: HBoxContainer = %CoinContainer
@onready var coin_label: Label = %CoinLabel

@onready var up_container: HBoxContainer = %UpContainer
@onready var up_label: Label = %UpLabel

@onready var potion_container: HBoxContainer = %PotionContainer
@onready var potion_label: Label = %PotionLabel

var coin_tween: Tween
var up_tween: Tween

#血条格子参数：1 滴血 = 1 格
const PIP_SIZE := Vector2( 16 , 10 )
const PIP_GAP : int = 0
const PIP_FILL_COLOR := Color( 0.83 , 0.24 , 0.21 )
const PIP_FILL_BORDER := Color( 0.33 , 0.06 , 0.06 )
const PIP_EMPTY_COLOR := Color( 0.10 , 0.09 , 0.11 )
const PIP_EMPTY_BORDER := Color( 0.28 , 0.13 , 0.15 )
#血条左端 x（与 HPMarginContainer 的 offset_left 一致）与血瓶模块间距
const HP_BAR_LEFT : float = 24.0
const POTION_GAP : float = 6.0

var _pip_style_filled : StyleBoxFlat
var _pip_style_empty : StyleBoxFlat


func _ready() -> void:
	_pip_style_filled = _make_pip_style( PIP_FILL_COLOR , PIP_FILL_BORDER )
	_pip_style_empty = _make_pip_style( PIP_EMPTY_COLOR , PIP_EMPTY_BORDER )
	Messages.player_health_changed.connect( update_health_bar )
	Messages.coin_collected.connect( _on_coin_collected )
	Messages.diamond_collected.connect( _on_diamond_collected )
	Messages.potion_changed.connect( _on_potion_changed )
	game_over.visible = false
	up_container.visible = false
	load_button.pressed.connect( _on_load_pressed )
	quit_button.pressed.connect( _on_quit_pressed )
	#玩家先于 HUD 生成时主动同步一次，避免初始血条为空
	var player : Player = get_tree().get_first_node_in_group( "Player" )
	if player:
		update_health_bar( player.hp , player.max_hp )
		_on_potion_changed( player.potion )
	pass



func _make_pip_style( bg_color : Color , border_color : Color ) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_border_width_all( 1 )
	#胶囊形：圆角半径 = 格子高度的一半（6/2）
	return style



#1 滴血 = 1 格：按 max_hp 构建格子，当前 hp 格填充红色，其余为空槽
func update_health_bar( hp : float , max_hp : float ) -> void:
	var total : int = clampi( int( round( max_hp ) ) , 0 , 999 )
	#剩余不足 1 滴也保留最后一格显示（向上取整）
	var current : int = clampi( int( ceil( hp ) ) , 0 , total )
	if hp_container.get_child_count() != total:
		_rebuild_pips( total )
	#框体内宽 = 左边距19 + 每格(宽+间隔) - 末尾间隔 + 右边距3
	hp_margin_container.size.x = 22 + total * ( int( PIP_SIZE.x ) + PIP_GAP ) - PIP_GAP
	#血瓶模块紧贴血条右侧：血条宽度随 max_hp 变化，这里按血条实际宽度重新定位
	potion_container.position.x = HP_BAR_LEFT + hp_margin_container.size.x + POTION_GAP
	for i in total:
		var pip : Panel = hp_container.get_child( i ) as Panel
		pip.add_theme_stylebox_override( "panel" , _pip_style_filled if i < current else _pip_style_empty )
	pass


#max_hp 变化（如生命上限提升）时重建整排格子
func _rebuild_pips( total : int ) -> void:
	for child in hp_container.get_children():
		child.free()
	for i in total:
		var pip := Panel.new()
		pip.custom_minimum_size = PIP_SIZE
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pip.add_theme_stylebox_override( "panel" , _pip_style_empty )
		hp_container.add_child( pip )
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


#血瓶数量变化时实时刷新计数显示（数据唯一来源是 Player.potion，避免显示与数据不同步）
func _on_potion_changed( count : int ) -> void:
	potion_label.text = str( count )
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
