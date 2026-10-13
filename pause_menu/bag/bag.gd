class_name BagPanel extends Control
## 背包界面（挂在 PauseMenu 的 Bag 节点上）
## 显示范围严格限定在 Bag 节点矩形内。
## 打开背包即进入“物品选择模式”：方向键或鼠标点击在格子间移动选中框，底部固定栏显示物品描述；
## 通过本界面内的“退出”按钮或 ui_cancel(Esc) 退出选择模式。
## 数据全部来自 Inventory 单例，监听 inventory_changed 自动刷新。

signal exit_requested

const SLOT_COLUMNS : int = 5
const SLOT_ROWS : int = 4
const SLOT_SIZE : int = 48
const SLOT_H_GAP : int = 8
const SLOT_V_GAP : int = 4

const UI_FONT := preload( "res://general/fonts/AaXiangSuJiangHu-Ben-2.ttf" )

const BG_COLOR := Color(0.588, 0.424, 0.424, 1.0)
const BAG_BORDER_COLOR := Color("3e3546ff")
const BAG_CORNER_RADIUS : int = 8
const SLOT_BG_COLOR := Color(0.0, 0.0, 0.0, 0.416)
const SLOT_BORDER_COLOR := Color(1.0, 1.0, 1.0, 0.9)
const SELECT_BORDER_COLOR := Color( 1.0 , 0.84 , 0.31 , 1.0 )
const COUNT_COLOR := Color( 1 , 1 , 1 , 1 )

var _slot_panels : Array[ Panel ] = []
var _select_frames : Array[ Panel ] = []
var _description_label : Label
var _active : bool = false
var _selected_index : int = 0


func _ready() -> void:
	#背包根本身不拦截鼠标；子节点中的遮挡层负责在选择模式下吞掉点击
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_background()
	_build_input_blocker()
	_build_grid()
	_build_description_bar()
	_build_exit_button()
	Inventory.inventory_changed.connect( _refresh )
	visibility_changed.connect( _on_visibility_changed )
	_refresh()
	_update_selection_view()
	pass


#构建背景与标题（铺满 Bag 矩形，圆角描边面板）
func _build_background() -> void:
	var bg := Panel.new()
	bg.name = "Background"
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset( Control.PRESET_FULL_RECT )
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = BG_COLOR
	bg_style.border_color = BAG_BORDER_COLOR
	bg_style.set_border_width_all( 2 )
	bg_style.set_corner_radius_all( BAG_CORNER_RADIUS )
	bg.add_theme_stylebox_override( "panel" , bg_style )
	add_child( bg )
	var title := Label.new()
	title.name = "Title"
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.text = "背包"
	title.position = Vector2( 12 , 7 )
	title.add_theme_font_override( "font" , UI_FONT )
	title.add_theme_font_size_override( "font_size" , 16 )
	add_child( title )
	pass


#透明遮挡层：选择模式下吞掉背包区域内的鼠标点击，
#使后面的暂停菜单按钮（含背包按钮本身）不可点，只能通过“退出”按钮离开
func _build_input_blocker() -> void:
	var blocker := Control.new()
	blocker.name = "InputBlocker"
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	blocker.set_anchors_preset( Control.PRESET_FULL_RECT )
	add_child( blocker )
	pass


#构建居中网格（5 列 × 4 行，格子等大、间距均匀）
func _build_grid() -> void:
	var center := CenterContainer.new()
	center.name = "GridCenter"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_preset( Control.PRESET_FULL_RECT )
	center.offset_top = 24.0
	center.offset_bottom = -27.0
	add_child( center )
	var grid := GridContainer.new()
	grid.name = "Grid"
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.columns = SLOT_COLUMNS
	grid.add_theme_constant_override( "h_separation" , SLOT_H_GAP )
	grid.add_theme_constant_override( "v_separation" , SLOT_V_GAP )
	center.add_child( grid )
	for i in Inventory.SLOT_CAPACITY:
		grid.add_child( _make_slot() )
	pass


#构建单个格子：底板 + 物品图标 + 右下角数量 + 选中框（默认隐藏）
func _make_slot() -> Panel:
	var slot := Panel.new()
	slot.custom_minimum_size = Vector2( SLOT_SIZE , SLOT_SIZE )
	#格子本身接收点击以支持鼠标选中（图标/数量/选中框仍 IGNORE，点击落到格子面板）
	slot.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = SLOT_BG_COLOR
	style.border_color = SLOT_BORDER_COLOR
	style.set_border_width_all( 1 )
	style.set_corner_radius_all( 2 )
	style.content_margin_left = 0.0
	style.content_margin_right = 0.0
	style.content_margin_top = 0.0
	style.content_margin_bottom = 0.0
	slot.add_theme_stylebox_override( "panel" , style )
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.set_anchors_preset( Control.PRESET_FULL_RECT )
	icon.offset_left = 5.0
	icon.offset_top = 5.0
	icon.offset_right = -5.0
	icon.offset_bottom = -5.0
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.visible = false
	slot.add_child( icon )
	var count := Label.new()
	count.name = "Count"
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count.set_anchors_preset( Control.PRESET_BOTTOM_RIGHT )
	count.offset_left = -20.0
	count.offset_top = -14.0
	count.offset_right = -3.0
	count.offset_bottom = -2.0
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	count.add_theme_font_override( "font" , UI_FONT )
	count.add_theme_font_size_override( "font_size" , 12 )
	count.add_theme_color_override( "font_color" , COUNT_COLOR )
	count.add_theme_color_override( "font_outline_color" , Color( 0 , 0 , 0 , 1 ) )
	count.add_theme_constant_override( "outline_size" , 3 )
	count.visible = false
	slot.add_child( count )
	#选中高亮框（透明底+金色描边，覆盖在格子最上层）
	var frame := Panel.new()
	frame.name = "SelectFrame"
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.set_anchors_preset( Control.PRESET_FULL_RECT )
	frame.offset_left = -2.0
	frame.offset_top = -2.0
	frame.offset_right = 2.0
	frame.offset_bottom = 2.0
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color( 0 , 0 , 0 , 0 )
	frame_style.border_color = SELECT_BORDER_COLOR
	frame_style.set_border_width_all( 2 )
	frame_style.set_corner_radius_all( 3 )
	frame.add_theme_stylebox_override( "panel" , frame_style )
	frame.visible = false
	slot.add_child( frame )
	var slot_index : int = _slot_panels.size()
	slot.gui_input.connect( func( ev : InputEvent ) -> void: _on_slot_gui_input( slot_index , ev ) )
	_slot_panels.append( slot )
	_select_frames.append( frame )
	return slot


#底部固定描述栏（位置固定在网格下方，不遮挡格子与其他 UI）
func _build_description_bar() -> void:
	var bar_bg := ColorRect.new()
	bar_bg.name = "DescBg"
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_bg.color = Color(0.0, 0.0, 0.0, 0.0)
	bar_bg.position = Vector2( 2 , 230 )
	bar_bg.size = Vector2( 395 , 21 )
	add_child( bar_bg )
	_description_label = Label.new()
	_description_label.name = "Description"
	_description_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_description_label.position = Vector2( 8 , 231 )
	_description_label.size = Vector2( 383 , 19 )
	_description_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_description_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_description_label.add_theme_font_override( "font" , UI_FONT )
	_description_label.add_theme_font_size_override( "font_size" , 12 )
	_description_label.add_theme_color_override( "font_color" , Color.WHITE )
	_description_label.add_theme_color_override( "font_outline_color" , Color( 0 , 0 , 0 , 1 ) )
	_description_label.add_theme_constant_override( "outline_size" , 3 )
	_description_label.text = ""
	add_child( _description_label )
	pass


#“退出”按钮：位于背包按钮正下方（Bag 是 BagButton 子节点，需扣除 Bag 原点偏移）
func _build_exit_button() -> void:
	var btn := Button.new()
	btn.name = "ExitButton"
	btn.text = "退出"
	btn.position = Vector2( -46 , 0 )
	btn.size = Vector2( 37 , 12 )
	btn.add_theme_font_override( "font" , UI_FONT )
	btn.add_theme_font_size_override( "font_size" , 12 )
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color( 0.12 , 0.13 , 0.15 , 0.9 )
	normal.border_color = SLOT_BORDER_COLOR
	normal.set_border_width_all( 1 )
	normal.set_corner_radius_all( 4 )
	normal.content_margin_left = 4.0
	normal.content_margin_right = 4.0
	normal.content_margin_top = 0.0
	normal.content_margin_bottom = 0.0
	var hover := normal.duplicate()
	hover.border_color = SELECT_BORDER_COLOR
	var pressed := normal.duplicate()
	pressed.bg_color = Color( 0.12156863 , 0.41960785 , 0.5803922 , 0.5 )
	btn.add_theme_stylebox_override( "normal" , normal )
	btn.add_theme_stylebox_override( "hover" , hover )
	btn.add_theme_stylebox_override( "pressed" , pressed )
	btn.add_theme_stylebox_override( "focus" , StyleBoxEmpty.new() )
	btn.pressed.connect( func() -> void: exit_requested.emit() )
	add_child( btn )
	pass


func _on_visibility_changed() -> void:
	_active = visible
	if _active:
		#进入选择模式：默认选中第一个有物品的格子（无物品则首格）
		_selected_index = 0
		for i in Inventory.SLOT_CAPACITY:
			if Inventory.get_slot_item( i ) != null:
				_selected_index = i
				break
		_update_selection_view()
	pass


#选择模式下方向键只在背包格子间移动；ui_cancel(Esc)等同“退出”按钮；pause 键被吞掉
func _input( event : InputEvent ) -> void:
	if not _active:
		return
	if event.is_action_pressed( "left" , true ) or event.is_action_pressed( "right" , true ) \
			or event.is_action_pressed( "up" , true ) or event.is_action_pressed( "down" , true ):
		get_viewport().set_input_as_handled()
		_move_selection( event )
	elif event.is_action_pressed( "ui_cancel" ):
		#Esc 与“退出”按钮等效：关闭背包、返回上一级
		get_viewport().set_input_as_handled()
		exit_requested.emit()
	elif event.is_action_pressed( "pause" ):
		#暂停键在选择模式中吞掉，防止直接关闭整个暂停菜单
		get_viewport().set_input_as_handled()
	pass


func _move_selection( event : InputEvent ) -> void:
	var col : int = _selected_index % SLOT_COLUMNS
	#行号按格数向下取整（丢弃小数）是预期行为
	@warning_ignore( "integer_division" )
	var row : int = _selected_index / SLOT_COLUMNS
	if event.is_action_pressed( "left" , true ):
		col = maxi( 0 , col - 1 )
	elif event.is_action_pressed( "right" , true ):
		col = mini( SLOT_COLUMNS - 1 , col + 1 )
	elif event.is_action_pressed( "up" , true ):
		row = maxi( 0 , row - 1 )
	elif event.is_action_pressed( "down" , true ):
		row = mini( SLOT_ROWS - 1 , row + 1 )
	_selected_index = row * SLOT_COLUMNS + col
	_update_selection_view()
	pass


#鼠标点击格子：左键选中该格（空格也可选中，与键盘选中行为一致）
func _on_slot_gui_input( index : int , event : InputEvent ) -> void:
	if not _active:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_selected_index = index
		_update_selection_view()
	pass


#刷新选中框与描述栏
func _update_selection_view() -> void:
	for i in Inventory.SLOT_CAPACITY:
		_select_frames[ i ].visible = ( _active and i == _selected_index )
	if not _active:
		_description_label.text = ""
		return
	var item : ItemData = Inventory.get_slot_item( _selected_index )
	if item == null:
		_description_label.text = ""
	elif item.description.is_empty():
		_description_label.text = item.item_name
	else:
		_description_label.text = "%s：%s" % [ item.item_name , item.description ]
	pass


#按 Inventory 数据刷新全部格子
func _refresh() -> void:
	for i in Inventory.SLOT_CAPACITY:
		var slot : Panel = _slot_panels[ i ]
		var icon : TextureRect = slot.get_node( "Icon" )
		var count : Label = slot.get_node( "Count" )
		var item : ItemData = Inventory.get_slot_item( i )
		var amount : int = Inventory.get_slot_amount( i )
		if item != null and amount > 0:
			icon.texture = item.icon
			icon.visible = item.icon != null
			count.text = str( amount )
			count.visible = true
			slot.tooltip_text = item.item_name
		else:
			icon.texture = null
			icon.visible = false
			count.text = ""
			count.visible = false
			slot.tooltip_text = ""
	_update_selection_view()
	pass
