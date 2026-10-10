class_name ShopUI extends CanvasLayer

## NPC 商店交互界面（全部代码构建，不依赖 .tscn，与 npc_1.gd 的对话框做法一致）
##
## 流程：NPC 对话读完最后一段 → open() 弹出选项面板（商店 / 离开）
##       → 选「商店」进入商店界面 → 选「离开」关闭全部面板并交还操作权
##
## 面板打开期间用 get_tree().paused 冻结整棵场景树，玩家无法移动 / 跳跃 / 攻击，
## 方向键也只会用于切换选项；关闭时只解除“本界面自己造成的”暂停。
## 与 pause_menu.tscn 相同：process_mode = ALWAYS，暂停期间仍能接收输入。

signal closed

const UI_FONT : FontFile = preload( "res://general/fonts/AaXiangSuJiangHu-Ben-2.ttf" )
## 商店在售道具：目前只有已开发完成的磁铁
const MAGNET_ITEM : ItemData = preload( "res://pause_menu/bag/items/magnet.tres" )
## 磁铁售价（金币）
const MAGNET_PRICE : int = 100

#选项面板的两个固定选项
const CHOICE_SHOP : int = 0
const CHOICE_LEAVE : int = 1
#商店界面的两个按钮
const SHOP_BUY : int = 0
const SHOP_CLOSE : int = 1

#配色沿用背包界面（bag.gd）：深色木框 + 金色选中描边
const PANEL_BG := Color( 0.588 , 0.424 , 0.424 , 1.0 )
const PANEL_BORDER := Color( "3e3546ff" )
const ROW_BG := Color( 0 , 0 , 0 , 0.35 )
const ROW_BORDER := Color( 1 , 1 , 1 , 0.25 )
const SELECT_COLOR := Color( 1.0 , 0.84 , 0.31 , 1.0 )
const PRICE_COLOR := Color( 1.0 , 0.84 , 0.31 , 1.0 )
const WARN_COLOR := Color( 1.0 , 0.45 , 0.4 , 1.0 )
const OK_COLOR := Color( 0.55 , 1.0 , 0.6 , 1.0 )

const MESSAGE_TEXT_OK : String = "购买成功！"
const MESSAGE_TEXT_POOR : String = "金币不足，无法购买"
const MESSAGE_TEXT_FULL : String = "背包已满，无法购买"

#售罄标记：道具行整体变淡的透明度 + 盖在格子上的文字
const SOLD_OUT_ALPHA : float = 0.35
const SOLD_OUT_TEXT : String = "已售罄"

var _screen : Control
var _choice_root : Panel
var _shop_root : Panel
var _choice_rows : Array[ Panel ] = []
var _shop_rows : Array[ Panel ] = []
var _coin_label : Label
var _message_label : Label
#磁铁格子里会随售罄变淡的内容（图标 / 名称 / 售价）与盖在上面的“已售罄”
var _item_fade_nodes : Array[ CanvasItem ] = []
var _sold_out_label : Label
var _selected_choice : int = CHOICE_SHOP
var _selected_shop : int = SHOP_BUY
#磁铁是否已售出：买过一次后置位，重开界面仍然保持售罄
var _sold_out : bool = false

#界面刚打开的这一帧不接收输入：触发对话的那次按键不能顺带确认掉首个选项
var _accept_input : bool = false
#暂停是否由本界面造成：是则关闭时恢复，否（外部已暂停）则保持原样
var _paused_by_self : bool = false

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
	_build_shop_panel()
	visible = false
	pass


# ---------- 对外接口 ----------

## 打开选项面板并锁定玩家操作
func open() -> void:
	_selected_choice = CHOICE_SHOP
	_selected_shop = SHOP_BUY
	_set_message( "" )
	_refresh_choice_view()
	_refresh_shop_view()
	_shop_root.visible = false
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
	_shop_root.visible = false
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


#选项面板：屏幕居中，固定两个选项（商店 / 离开）
func _build_choice_panel() -> void:
	_choice_root = _make_center_panel( Vector2( 200 , 120 ) )
	_add_title( _choice_root , "有什么可以帮你的？" )
	var options : Array[ String ] = [ "商店" , "离开" ]
	for i in options.size():
		var row := _make_option_row( options[ i ] , Vector2( 160 , 28 ) )
		row.position = Vector2( 20 , 36 + i * 36 )
		row.gui_input.connect( _on_row_gui_input.bind( true , i ) )
		_choice_root.add_child( row )
		_choice_rows.append( row )
	pass


#商店界面：商品行（图标 / 名称 / 售价）+ 提示信息 + 购买、关闭按钮 + 持有金币
func _build_shop_panel() -> void:
	_shop_root = _make_center_panel( Vector2( 320 , 190 ) )
	_add_title( _shop_root , "商店" )

	var item_row := Panel.new()
	item_row.name = "ItemRow"
	item_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item_row.offset_left = 16.0
	item_row.offset_top = 36.0
	item_row.offset_right = 304.0
	item_row.offset_bottom = 92.0
	item_row.add_theme_stylebox_override( "panel" , _item_row_style )
	_shop_root.add_child( item_row )

	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture = MAGNET_ITEM.icon
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.offset_left = 10.0
	icon.offset_top = 8.0
	icon.offset_right = 50.0
	icon.offset_bottom = 48.0
	item_row.add_child( icon )

	#名称与售价左对齐，右侧留给“已售罄”标记
	var item_name_label := _make_label( MAGNET_ITEM.item_name , Vector2( 60 , 8 ) , Vector2( 130 , 20 ) , 14 , Color.WHITE , HORIZONTAL_ALIGNMENT_LEFT )
	var item_price_label := _make_label( "%d 金币" % MAGNET_PRICE , Vector2( 60 , 30 ) , Vector2( 130 , 18 ) , 12 , PRICE_COLOR , HORIZONTAL_ALIGNMENT_LEFT )
	item_row.add_child( item_name_label )
	item_row.add_child( item_price_label )
	_item_fade_nodes = [ icon , item_name_label , item_price_label ]

	#“已售罄”盖在格子右侧：默认隐藏，买过一次后显示
	_sold_out_label = _make_label( SOLD_OUT_TEXT , Vector2( 192 , 8 ) , Vector2( 80 , 40 ) , 14 , WARN_COLOR )
	_sold_out_label.add_theme_color_override( "font_outline_color" , Color( 0 , 0 , 0 , 1 ) )
	_sold_out_label.add_theme_constant_override( "outline_size" , 4 )
	_sold_out_label.visible = false
	item_row.add_child( _sold_out_label )

	_message_label = _make_label( "" , Vector2( 0 , 98 ) , Vector2( 320 , 18 ) , 12 , OK_COLOR )
	_message_label.anchor_right = 1.0
	_message_label.offset_right = 0.0
	_shop_root.add_child( _message_label )

	var buttons : Array[ String ] = [ "购买" , "关闭" ]
	for i in buttons.size():
		var row := _make_option_row( buttons[ i ] , Vector2( 130 , 26 ) )
		row.position = Vector2( 24 + i * 142 , 122 )
		row.gui_input.connect( _on_row_gui_input.bind( false , i ) )
		_shop_root.add_child( row )
		_shop_rows.append( row )

	_coin_label = _make_label( "" , Vector2( 0 , 158 ) , Vector2( 320 , 18 ) , 12 , Color.WHITE )
	_coin_label.anchor_right = 1.0
	_coin_label.offset_right = 0.0
	_shop_root.add_child( _coin_label )
	pass


func _make_center_panel( size : Vector2 ) -> Panel:
	var panel := Panel.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
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
	elif _shop_root.visible:
		_handle_shop_input( event )
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


#商店界面：上下键在“购买 / 关闭”间切换，Esc 返回选项面板
func _handle_shop_input( event : InputEvent ) -> void:
	if event.is_action_pressed( "up" ) or event.is_action_pressed( "down" ):
		get_viewport().set_input_as_handled()
		_selected_shop = wrapi( _selected_shop + 1 , 0 , _shop_rows.size() )
		_refresh_shop_view()
		Audio.ui_focus_change()
	elif event.is_action_pressed( "ui_cancel" ):
		get_viewport().set_input_as_handled()
		_back_to_choice()
	elif event.is_action_pressed( "action" ) or event.is_action_pressed( "ui_accept" ):
		get_viewport().set_input_as_handled()
		if _selected_shop == SHOP_BUY:
			_buy_magnet()
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
		_selected_shop = index
		_refresh_shop_view()
		if index == SHOP_BUY:
			_buy_magnet()
		else:
			_back_to_choice()
	pass


# ---------- 流程 ----------

func _choose( choice : int ) -> void:
	Audio.ui_select()
	if choice == CHOICE_SHOP:
		_choice_root.visible = false
		_shop_root.visible = true
		_set_message( "" )
		_refresh_shop_view()
	else:
		close()
	pass


func _back_to_choice() -> void:
	#与背包界面的“退出”一致：返回上一级不额外播音（Audio.ui_cancel 的音源未配置）
	_shop_root.visible = false
	_choice_root.visible = true
	_selected_choice = CHOICE_SHOP
	_refresh_choice_view()
	pass


#购买校验：金币不足只提示不扣款；足够则先入背包再扣金币，背包满时不扣款
func _buy_magnet() -> void:
	if _sold_out:
		#已售罄：不能再买，格子上已有标记
		return
	var player : Player = get_tree().get_first_node_in_group( "Player" ) as Player
	if player == null:
		return
	if player.coin < MAGNET_PRICE:
		Audio.ui_error()
		_set_message( MESSAGE_TEXT_POOR )
		return
	if Inventory.add_item( MAGNET_ITEM , 1 ) <= 0:
		Audio.ui_error()
		_set_message( MESSAGE_TEXT_FULL )
		return
	player.coin -= MAGNET_PRICE
	#与 coin_pickup.gd 一致：金币变化后广播一次，HUD 立即同步
	Messages.coin_collected.emit( player.coin )
	Audio.ui_success()
	_set_message( MESSAGE_TEXT_OK )
	#售出后磁铁格子变淡并盖上“已售罄”
	_sold_out = true
	_refresh_shop_view()
	pass


# ---------- 刷新 ----------

func _refresh_choice_view() -> void:
	for i in _choice_rows.size():
		_choice_rows[ i ].add_theme_stylebox_override( "panel" ,
			_row_selected_style if i == _selected_choice else _row_normal_style )
	pass


func _refresh_shop_view() -> void:
	for i in _shop_rows.size():
		_shop_rows[ i ].add_theme_stylebox_override( "panel" ,
			_row_selected_style if i == _selected_shop else _row_normal_style )
	#售罄标记：磁铁图标 / 名称 / 售价变淡，“已售罄”盖在格子右侧
	var item_alpha : float = SOLD_OUT_ALPHA if _sold_out else 1.0
	for node in _item_fade_nodes:
		node.modulate.a = item_alpha
	if _sold_out_label != null:
		_sold_out_label.visible = _sold_out
	var player : Player = get_tree().get_first_node_in_group( "Player" ) as Player
	if _coin_label != null:
		_coin_label.text = "持有金币：%d" % ( player.coin if player != null else 0 )
	pass


func _set_message( text : String ) -> void:
	if _message_label == null:
		return
	_message_label.text = text
	_message_label.add_theme_color_override( "font_color" , WARN_COLOR if text != MESSAGE_TEXT_OK else OK_COLOR )
	pass


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
