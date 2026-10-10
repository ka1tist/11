class_name UpgradeUI extends CanvasLayer

## NPC 强化界面（全部代码构建，不依赖 .tscn，与 npc_1.gd 的对话框 / shop_ui.gd 的写法一致）
##
## 流程：NPC 对话读完最后一段 → open() 弹出选项面板（强化 / 离开）
##       → 选「强化」进入强化界面 → 消耗钻石提升攻击力 → 选「离开」关闭面板并交还操作权
##
## 规则：强化一次消耗 4 个钻石、攻击力 +0.5；钻石不足只提示不扣材料。
## 面板打开期间用 get_tree().paused 冻结整棵场景树，玩家无法移动 / 跳跃 / 攻击，
## 方向键只用于切换选项；关闭时只解除“本界面自己造成的”暂停。

signal closed

const UI_FONT : FontFile = preload( "res://general/fonts/AaXiangSuJiangHu-Ben-2.ttf" )
## 强化成功音效：与宝箱获取用同一个音频文件
const UPGRADE_AUDIO : AudioStream = preload( "res://general/audio/宝箱获取.wav" )
## 每次强化消耗的钻石数
const UPGRADE_COST : int = 4
## 每次强化提升的攻击力
const ATTACK_GAIN : float = 0.5
## 连点保护窗口：这段时间内的第二次强化点击会被忽略，避免一次操作被重复执行
const ACTION_COOLDOWN_MSEC : int = 300

#选项面板的两个固定选项
const CHOICE_UPGRADE : int = 0
const CHOICE_LEAVE : int = 1
#强化界面的两个按钮
const UPGRADE_CONFIRM : int = 0
const UPGRADE_CLOSE : int = 1

#配色沿用背包 / 商店界面：深色木框 + 金色选中描边
const PANEL_BG := Color( 0.588 , 0.424 , 0.424 , 1.0 )
const PANEL_BORDER := Color( "3e3546ff" )
const ROW_BG := Color( 0 , 0 , 0 , 0.35 )
const ROW_BORDER := Color( 1 , 1 , 1 , 0.25 )
const SELECT_COLOR := Color( 1.0 , 0.84 , 0.31 , 1.0 )
const VALUE_COLOR := Color( 1.0 , 0.84 , 0.31 , 1.0 )
const WARN_COLOR := Color( 1.0 , 0.45 , 0.4 , 1.0 )
const OK_COLOR := Color( 0.55 , 1.0 , 0.6 , 1.0 )

const MESSAGE_TEXT_OK : String = "强化成功！攻击力 +"
const MESSAGE_TEXT_POOR : String = "材料不足"

var _screen : Control
var _choice_root : Panel
var _upgrade_root : Panel
var _choice_rows : Array[ Panel ] = []
var _upgrade_rows : Array[ Panel ] = []
var _diamond_label : Label
var _attack_label : Label
var _message_label : Label
var _selected_choice : int = CHOICE_UPGRADE
var _selected_upgrade : int = UPGRADE_CONFIRM

#界面刚打开的这一帧不接收输入：触发对话的那次按键不能顺带确认掉首个选项
var _accept_input : bool = false
#暂停是否由本界面造成：是则关闭时恢复，否（外部已暂停）则保持原样
var _paused_by_self : bool = false
#上次强化的时间戳，用于连点保护
var _last_upgrade_msec : int = -99999

var _panel_style : StyleBoxFlat
var _row_normal_style : StyleBoxFlat
var _row_selected_style : StyleBoxFlat
var _item_row_style : StyleBoxFlat


func _ready() -> void:
	#暂停期间仍要接收输入
	process_mode = Node.PROCESS_MODE_ALWAYS
	#层级高于 HUD / 暂停菜单，避免被其他界面盖住
	layer = 20
	_panel_style = _make_panel_style()
	_row_normal_style = _make_row_style( false )
	_row_selected_style = _make_row_style( true )
	_item_row_style = _make_item_row_style()
	_build_screen()
	_build_choice_panel()
	_build_upgrade_panel()
	visible = false
	pass


# ---------- 对外接口 ----------

## 打开选项面板并锁定玩家操作
func open() -> void:
	_selected_choice = CHOICE_UPGRADE
	_selected_upgrade = UPGRADE_CONFIRM
	_set_message( "" )
	_refresh_choice_view()
	_refresh_upgrade_view()
	_upgrade_root.visible = false
	_choice_root.visible = true
	visible = true
	_pause_game()
	_accept_input = false
	set_deferred( "_accept_input" , true )
	pass


## 关闭全部面板并把操作权交还玩家
func close() -> void:
	_accept_input = false
	visible = false
	_choice_root.visible = false
	_upgrade_root.visible = false
	_resume_game()
	closed.emit()
	pass


# ---------- 界面构建 ----------

func _build_screen() -> void:
	_screen = Control.new()
	_screen.name = "Screen"
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.set_anchors_preset( Control.PRESET_FULL_RECT )
	add_child( _screen )
	#半透明遮罩：挡住指向游戏世界的鼠标点击，同时压暗背景突出面板
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color( 0 , 0 , 0 , 0.55 )
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.set_anchors_preset( Control.PRESET_FULL_RECT )
	_screen.add_child( dim )
	pass


#选项面板：屏幕居中，固定两个选项（强化 / 离开）
func _build_choice_panel() -> void:
	_choice_root = _make_center_panel( Vector2( 200 , 120 ) )
	_add_title( _choice_root , "要变强吗？" )
	var options : Array[ String ] = [ "强化" , "离开" ]
	for i in options.size():
		var row := _make_option_row( options[ i ] , Vector2( 160 , 28 ) )
		row.position = Vector2( 20 , 36 + i * 36 )
		row.gui_input.connect( _on_row_gui_input.bind( true , i ) )
		_choice_root.add_child( row )
		_choice_rows.append( row )
	pass


#强化界面：材料行（钻石图标 / 名称 / 消耗量 / 持有量）+ 攻击力 + 提示 + 强化、关闭
func _build_upgrade_panel() -> void:
	_upgrade_root = _make_center_panel( Vector2( 320 , 200 ) )
	_add_title( _upgrade_root , "强化" )

	var item_row := Panel.new()
	item_row.name = "DiamondRow"
	item_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item_row.offset_left = 16.0
	item_row.offset_top = 34.0
	item_row.offset_right = 304.0
	item_row.offset_bottom = 90.0
	item_row.add_theme_stylebox_override( "panel" , _item_row_style )
	_upgrade_root.add_child( item_row )

	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture = preload( "res://general/sprites/diamond-01.png" )
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.offset_left = 10.0
	icon.offset_top = 8.0
	icon.offset_right = 50.0
	icon.offset_bottom = 48.0
	item_row.add_child( icon )

	item_row.add_child( _make_label( "钻石" , Vector2( 60 , 8 ) , Vector2( 120 , 20 ) , 14 , Color.WHITE , HORIZONTAL_ALIGNMENT_LEFT ) )
	item_row.add_child( _make_label( "消耗 %d 个" % UPGRADE_COST , Vector2( 60 , 30 ) , Vector2( 120 , 18 ) , 12 , VALUE_COLOR , HORIZONTAL_ALIGNMENT_LEFT ) )
	#持有数量：打开界面时自动刷新
	_diamond_label = _make_label( "" , Vector2( 184 , 8 ) , Vector2( 88 , 40 ) , 14 , Color.WHITE )
	item_row.add_child( _diamond_label )

	#当前攻击力：强化成功后数值变化并做一次缩放 / 变色反馈
	_attack_label = _make_label( "" , Vector2( 0 , 96 ) , Vector2( 320 , 22 ) , 14 , VALUE_COLOR )
	_attack_label.anchor_right = 1.0
	_attack_label.offset_right = 0.0
	_upgrade_root.add_child( _attack_label )

	_message_label = _make_label( "" , Vector2( 0 , 122 ) , Vector2( 320 , 18 ) , 12 , OK_COLOR )
	_message_label.anchor_right = 1.0
	_message_label.offset_right = 0.0
	_upgrade_root.add_child( _message_label )

	var buttons : Array[ String ] = [ "强化" , "关闭" ]
	for i in buttons.size():
		var row := _make_option_row( buttons[ i ] , Vector2( 130 , 26 ) )
		row.position = Vector2( 24 + i * 142 , 148 )
		row.gui_input.connect( _on_row_gui_input.bind( false , i ) )
		_upgrade_root.add_child( row )
		_upgrade_rows.append( row )
	pass


func _make_center_panel( size : Vector2 ) -> Panel:
	var panel := Panel.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	#居中锚点：任何分辨率下都保持在屏幕中央
	panel.set_anchors_preset( Control.PRESET_CENTER )
	panel.offset_left = -size.x * 0.5
	panel.offset_top = -size.y * 0.5
	panel.offset_right = size.x * 0.5
	panel.offset_bottom = size.y * 0.5
	panel.add_theme_stylebox_override( "panel" , _panel_style )
	_screen.add_child( panel )
	return panel


func _add_title( panel : Panel , text : String ) -> void:
	var title := _make_label( text , Vector2( 0 , 6 ) , Vector2( 320 , 22 ) , 16 , Color.WHITE )
	title.anchor_right = 1.0
	title.offset_right = 0.0
	panel.add_child( title )
	pass


#一行可选项：深色底板 + 居中文字，选中时换成金色描边（由 _refresh_*_view 切换）
func _make_option_row( text : String , row_size : Vector2 ) -> Panel:
	var row := Panel.new()
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.offset_right = row_size.x
	row.offset_bottom = row_size.y
	row.add_theme_stylebox_override( "panel" , _row_normal_style )
	var label := Label.new()
	label.name = "Text"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_anchors_preset( Control.PRESET_FULL_RECT )
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override( "font" , UI_FONT )
	label.add_theme_font_size_override( "font_size" , 14 )
	label.add_theme_color_override( "font_color" , Color.WHITE )
	label.text = text
	row.add_child( label )
	return row


func _make_label( text : String , pos : Vector2 , size : Vector2 , font_size : int , color : Color ,
		align : int = HORIZONTAL_ALIGNMENT_CENTER ) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = text
	label.position = pos
	label.offset_right = pos.x + size.x
	label.offset_bottom = pos.y + size.y
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override( "font" , UI_FONT )
	label.add_theme_font_size_override( "font_size" , font_size )
	label.add_theme_color_override( "font_color" , color )
	return label


func _make_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.border_color = PANEL_BORDER
	style.set_border_width_all( 2 )
	style.set_corner_radius_all( 8 )
	return style


func _make_row_style( selected : bool ) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = ROW_BG
	style.border_color = SELECT_COLOR if selected else ROW_BORDER
	style.set_border_width_all( 2 if selected else 1 )
	style.set_corner_radius_all( 3 )
	return style


func _make_item_row_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color( 0 , 0 , 0 , 0.25 )
	style.border_color = ROW_BORDER
	style.set_border_width_all( 1 )
	style.set_corner_radius_all( 4 )
	return style


# ---------- 输入 ----------

func _input( event : InputEvent ) -> void:
	if not _accept_input:
		return
	if _choice_root.visible:
		_handle_choice_input( event )
	elif _upgrade_root.visible:
		_handle_upgrade_input( event )
	pass


#选项面板：上下键切换并高亮，交互键/回车确认，Esc 等同“离开”
func _handle_choice_input( event : InputEvent ) -> void:
	if event.is_action_pressed( "up" ):
		_move_choice_selection( -1 )
	elif event.is_action_pressed( "down" ):
		_move_choice_selection( 1 )
	elif event.is_action_pressed( "ui_cancel" ):
		get_viewport().set_input_as_handled()
		_choose( CHOICE_LEAVE )
	elif event.is_action_pressed( "action" ) or event.is_action_pressed( "ui_accept" ):
		get_viewport().set_input_as_handled()
		_choose( _selected_choice )
	pass


#强化界面：上下键在“强化 / 关闭”间切换，Esc 返回选项面板
func _handle_upgrade_input( event : InputEvent ) -> void:
	if event.is_action_pressed( "up" ) or event.is_action_pressed( "down" ):
		get_viewport().set_input_as_handled()
		_selected_upgrade = wrapi( _selected_upgrade + 1 , 0 , _upgrade_rows.size() )
		_refresh_upgrade_view()
		Audio.ui_focus_change()
	elif event.is_action_pressed( "ui_cancel" ):
		get_viewport().set_input_as_handled()
		_back_to_choice()
	elif event.is_action_pressed( "action" ) or event.is_action_pressed( "ui_accept" ):
		get_viewport().set_input_as_handled()
		if _selected_upgrade == UPGRADE_CONFIRM:
			_upgrade_attack()
		else:
			_back_to_choice()
	pass


func _move_choice_selection( delta : int ) -> void:
	get_viewport().set_input_as_handled()
	_selected_choice = wrapi( _selected_choice + delta , 0 , _choice_rows.size() )
	_refresh_choice_view()
	Audio.ui_focus_change()
	pass


#鼠标左键点击选项行：选中并立即确认，行为与键盘一致
func _on_row_gui_input( event : InputEvent , is_choice : bool , index : int ) -> void:
	if not _accept_input:
		return
	if not ( event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT ):
		return
	if is_choice:
		_selected_choice = index
		_refresh_choice_view()
		_choose( index )
	else:
		_selected_upgrade = index
		_refresh_upgrade_view()
		if index == UPGRADE_CONFIRM:
			_upgrade_attack()
		else:
			_back_to_choice()
	pass


# ---------- 流程 ----------

func _choose( choice : int ) -> void:
	Audio.ui_select()
	if choice == CHOICE_UPGRADE:
		_choice_root.visible = false
		_upgrade_root.visible = true
		_set_message( "" )
		_refresh_upgrade_view()
	else:
		close()
	pass


func _back_to_choice() -> void:
	#与背包界面的“退出”一致：返回上一级不额外播音（Audio.ui_cancel 的音源未配置）
	_upgrade_root.visible = false
	_choice_root.visible = true
	_selected_choice = CHOICE_UPGRADE
	_refresh_choice_view()
	pass


## 强化校验：钻石不足只提示不扣材料；足够则扣钻石 + 攻击力 +0.5 + 播音效 + 成功反馈
func _upgrade_attack() -> void:
	#连点保护：短时间内重复点击不生效，避免一次操作被重复扣除
	var now : int = Time.get_ticks_msec()
	if now - _last_upgrade_msec < ACTION_COOLDOWN_MSEC:
		return
	var player : Player = get_tree().get_first_node_in_group( "Player" ) as Player
	if player == null:
		return
	if player.diamond < UPGRADE_COST:
		Audio.ui_error()
		_set_message( MESSAGE_TEXT_POOR , true )
		return
	_last_upgrade_msec = now
	player.diamond -= UPGRADE_COST
	#与钻石.gd 一致：钻石变化后广播一次，HUD 立即同步
	Messages.diamond_collected.emit( player.diamond )
	player.add_attack_power( ATTACK_GAIN )
	#攻击力加成属于永久进度：与钻石/宝箱同样即时落盘，避免死亡重生后回档
	SaveManager.save_progress()
	#音效与宝箱获取同一文件，按世界音效在玩家位置播放
	Audio.play_spatial_sound( UPGRADE_AUDIO , player.global_position )
	_set_message( MESSAGE_TEXT_OK + _format_attack( ATTACK_GAIN ) )
	_refresh_upgrade_view()
	_play_success_effect()
	pass


#成功反馈动效：攻击力数值先放大，再回弹并淡回原色
func _play_success_effect() -> void:
	if _attack_label == null:
		return
	_attack_label.pivot_offset = _attack_label.size * 0.5
	_attack_label.modulate = OK_COLOR
	var tween := create_tween()
	tween.tween_property( _attack_label , "scale" , Vector2( 1.35 , 1.35 ) , 0.1 )
	tween.tween_property( _attack_label , "scale" , Vector2.ONE , 0.25 )
	tween.parallel().tween_property( _attack_label , "modulate" , Color.WHITE , 0.25 )
	pass


# ---------- 刷新 ----------

func _refresh_choice_view() -> void:
	for i in _choice_rows.size():
		_choice_rows[ i ].add_theme_stylebox_override( "panel" ,
			_row_selected_style if i == _selected_choice else _row_normal_style )
	pass


func _refresh_upgrade_view() -> void:
	for i in _upgrade_rows.size():
		_upgrade_rows[ i ].add_theme_stylebox_override( "panel" ,
			_row_selected_style if i == _selected_upgrade else _row_normal_style )
	var player : Player = get_tree().get_first_node_in_group( "Player" ) as Player
	if _diamond_label != null:
		_diamond_label.text = "持有：%d" % ( player.diamond if player != null else 0 )
	if _attack_label != null:
		_attack_label.text = "当前攻击力：%s" % ( _format_attack( player.attack_area.damege ) if player != null else "0" )
	pass


func _set_message( text : String , warn : bool = false ) -> void:
	if _message_label == null:
		return
	_message_label.text = text
	_message_label.add_theme_color_override( "font_color" , WARN_COLOR if warn else OK_COLOR )
	pass


#攻击力可能是 1.5 这种带小数的值：整数不显示小数点
func _format_attack( value : float ) -> String:
	if is_equal_approx( value , roundf( value ) ):
		return str( int( roundf( value ) ) )
	return "%.1f" % value


# ---------- 暂停 / 恢复 ----------

func _pause_game() -> void:
	if get_tree().paused:
		#外部（如暂停菜单）已经暂停：只记录，不抢所有权
		_paused_by_self = false
		return
	get_tree().paused = true
	_paused_by_self = true
	pass


func _resume_game() -> void:
	if _paused_by_self:
		get_tree().paused = false
		_paused_by_self = false
	pass


func _exit_tree() -> void:
	#场景切换 / NPC 被销毁时，若是本界面暂停的必须恢复，否则整局卡在暂停
	_resume_game()
	pass