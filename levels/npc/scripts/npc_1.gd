class_name NPC1 extends NPC


#对话内容：每段为一次气泡展示，按交互键依次推进，末段后自动关闭并恢复移动
@export var dialog_lines : Array[String] = []

#交互检测区尺寸（宽×高，像素）
@export var detect_size : Vector2 = Vector2( 60 , 48 )
#对话框在 NPC 头顶的垂直偏移（像素，负值=向上），底部指针应靠近 NPC 头顶
@export var dialog_box_offset_y : float = -140.0
#文本在对话框贴图内的边距（左/右、上/下），避开木质边框与角落叶子装饰
@export var dialog_text_padding : Vector2 = Vector2( 6 , 4 )

#对话框样式参数
const DIALOGUE_TEXTURE_PATH := "res://levels/npc/sprites/dialogue_paper_3a.png"
const DIALOG_PATCH_LEFT := 34
const DIALOG_PATCH_RIGHT := 40
const DIALOG_FONT_SIZE : int = 10
const DIALOG_FADE_TIME : float = 0.12
const DIALOG_Z_INDEX : int = 10
const DIALOG_SCALE : float = 0.2

var _interaction_area : Area2D
var _dialog_box : Control
var _nine_patch : NinePatchRect
var _dialog_label : Label
var _tex_size : Vector2 = Vector2.ZERO
var _dialog_index : int = 0
var _is_talking : bool = false
var _tween : Tween


func _ready() -> void:
	super._ready()
	_setup_interaction_area()
	_setup_dialog_box()
	#场景加载时若玩家已在交互范围内（如出生点附近），一物理帧后直接显示交互提示
	await get_tree().physics_frame
	if is_instance_valid( _interaction_area ):
		for body in _interaction_area.get_overlapping_bodies():
			if body is Player:
				_on_body_entered( body )
				break
	pass


#构建交互检测区：Area2D + 矩形碰撞，mask=玩家层(16)、layer=0 不影响其他对象
func _setup_interaction_area() -> void:
	_interaction_area = Area2D.new()
	_interaction_area.name = "InteractionArea"
	_interaction_area.collision_layer = 0
	_interaction_area.collision_mask = 16
	add_child( _interaction_area )
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = detect_size
	shape.shape = rect
	_interaction_area.add_child( shape )
	_interaction_area.body_entered.connect( _on_body_entered )
	_interaction_area.body_exited.connect( _on_body_exited )
	pass


#构建对话框（世界空间，NPC 头顶）：Control + NinePatchRect + Label 全部代码构建
#不依赖 dialogue.tscn 场景文件，彻底避免 preload/load 的编辑器缓存问题
#NinePatchRect 九宫格缩放保持边角装饰固定，中心区域随文本长度伸缩
func _setup_dialog_box() -> void:
	#Control 根节点
	_dialog_box = Control.new()
	_dialog_box.visible = false
	_dialog_box.z_index = DIALOG_Z_INDEX
	_dialog_box.anchor_left = 0.0
	_dialog_box.anchor_top = 0.0
	_dialog_box.anchor_right = 0.0
	_dialog_box.anchor_bottom = 0.0
	_dialog_box.position = Vector2( 0.0 , dialog_box_offset_y )
	#等比例缩小 10 倍（贴图、文本、气泡整体缩放）
	_dialog_box.scale = Vector2( DIALOG_SCALE , DIALOG_SCALE )
	add_child( _dialog_box )
	#NinePatchRect 铺满 Control（anchors 0,0,1,1 + 零偏移），九宫格缩放
	_nine_patch = NinePatchRect.new()
	_nine_patch.anchor_right = 1.0
	_nine_patch.anchor_bottom = 1.0
	_nine_patch.offset_left = 0.0
	_nine_patch.offset_top = 0.0
	_nine_patch.offset_right = 0.0
	_nine_patch.offset_bottom = 0.0
	_nine_patch.texture = load( DIALOGUE_TEXTURE_PATH )
	_nine_patch.patch_margin_left = DIALOG_PATCH_LEFT
	_nine_patch.patch_margin_right = DIALOG_PATCH_RIGHT
	#记录贴图原始尺寸，用于保持高度不畸变
	if _nine_patch.texture:
		_tex_size = _nine_patch.texture.get_size()
	_dialog_box.add_child( _nine_patch )
	#Label 挂在 Control 根节点下（绘制在 NinePatchRect 之上），位置/尺寸在 _show_dialog_line 动态设置
	#Label 反向缩放 1/DIALOG_SCALE，抵消 Control 的缩放使文本保持原始字号不缩小
	_dialog_label = Label.new()
	_dialog_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dialog_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_dialog_label.add_theme_font_size_override( "font_size" , DIALOG_FONT_SIZE )
	_dialog_label.add_theme_color_override( "font_color" , Color.BLACK )
	_dialog_label.scale = Vector2( 1.0 / DIALOG_SCALE , 1.0 / DIALOG_SCALE )
	_dialog_box.add_child( _dialog_label )
	pass


func _on_body_entered( body : Node2D ) -> void:
	if body is not Player:
		return
	#连接全局交互信号：玩家按 action 键时 player.gd 发射 Messages.player_interacted
	if not Messages.player_interacted.is_connected( _on_player_interacted ):
		Messages.player_interacted.connect( _on_player_interacted )
	Messages.input_hint_changed.emit( "interact" )
	pass


func _on_body_exited( body : Node2D ) -> void:
	if body is not Player:
		return
	if Messages.player_interacted.is_connected( _on_player_interacted ):
		Messages.player_interacted.disconnect( _on_player_interacted )
	Messages.input_hint_changed.emit( "" )
	#玩家离开时若正在对话，直接结束并恢复移动
	if _is_talking:
		_end_dialog()
	pass


#玩家触发交互：未对话时开始对话，对话中时推进到下一段
func _on_player_interacted( _player : Player ) -> void:
	if _is_talking:
		_advance_dialog()
	else:
		_start_dialog()
	pass


#对话中持续朝向玩家：覆盖基类 _process，先让基类处理（TALKING 时直接返回冻结移动），
#再在对话状态下每帧根据玩家位置翻转 NPC 朝向
func _process( delta : float ) -> void:
	super._process( delta )
	if _is_talking:
		_face_player()
	pass


#根据玩家与 NPC 的水平相对位置翻转精灵朝向
func _face_player() -> void:
	var player := get_tree().get_first_node_in_group( "Player" ) as Node2D
	if player == null:
		return
	var diff : float = player.global_position.x - global_position.x
	_flip_sprite( 1.0 if diff > 0.0 else -1.0 )
	pass


#开始对话：停止 NPC 移动（状态优先级 TALKING > WALKING），显示第一段文本
func _start_dialog() -> void:
	_is_talking = true
	_dialog_index = 0
	start_talking()
	#对话开始立即朝向玩家
	_face_player()
	Messages.input_hint_changed.emit( "interact" )
	_show_dialog_line( dialog_lines[ _dialog_index ] if dialog_lines.size() > 0 else "" )
	pass


#推进对话：到达末段后自动关闭对话框并恢复移动
func _advance_dialog() -> void:
	_dialog_index += 1
	if _dialog_index >= dialog_lines.size():
		_end_dialog()
		return
	_show_dialog_line( dialog_lines[ _dialog_index ] )
	pass


#结束对话：隐藏对话框、恢复随机移动，按玩家是否仍在范围内决定提示状态
func _end_dialog() -> void:
	_is_talking = false
	_hide_dialog_box()
	stop_talking()
	if is_instance_valid( _interaction_area ):
		var player_in_range : bool = false
		for body in _interaction_area.get_overlapping_bodies():
			if body is Player:
				player_in_range = true
				break
		if player_in_range:
			Messages.input_hint_changed.emit( "interact" )
		else:
			Messages.input_hint_changed.emit( "" )
	pass


#显示指定文本行：按文本实际渲染尺寸计算气泡目标尺寸，设 Control + NinePatchRect + Label 的 size/position，
#最后淡入
func _show_dialog_line( text : String ) -> void:
	_dialog_label.text = text
	_dialog_box.visible = true
	if _tween:
		_tween.kill()
	_dialog_box.modulate.a = 0.0
	#用字体度量计算文本实际渲染尺寸
	var font := _dialog_label.get_theme_font( "font" )
	var text_width : float = 0.0
	var text_height : float = 0.0
	if font:
		text_width = font.get_string_size( text , HORIZONTAL_ALIGNMENT_LEFT , -1 , DIALOG_FONT_SIZE ).x
		text_height = font.get_height( DIALOG_FONT_SIZE )
	#高度固定为贴图原始高度，保持原比例不畸变；宽度需除以 DIALOG_SCALE 补偿缩放，
	#使视觉宽度 = 文本宽 + 边距×2（Label 反向缩放后视觉文本宽 = text_width）
	var box_height : float = _tex_size.y if _tex_size.y > 0.0 else 52.0
	var box_width : float = maxf( ( text_width + dialog_text_padding.x * 2.0 ) / DIALOG_SCALE , float( DIALOG_PATCH_LEFT + DIALOG_PATCH_RIGHT ) )
	#设 Control 尺寸与位置（水平居中于 NPC 上方，position 需乘以 scale 补偿缩放后的视觉宽度）
	_dialog_box.size = Vector2( box_width , box_height )
	_dialog_box.position = Vector2( -box_width * DIALOG_SCALE * 0.5 , dialog_box_offset_y )
	#NinePatchRect 显式设尺寸与位置，九宫格缩放：左右 patch 区域不变，中间拉伸
	_nine_patch.size = Vector2( box_width , box_height )
	_nine_patch.position = Vector2( 0.0 , 0.0 )
	#Label 反向缩放后视觉尺寸 = 原始尺寸，故 size 用文本实际尺寸；
	#position 需除以 DIALOG_SCALE 补偿 Control 缩放，使视觉边距与 dialog_text_padding 一致
	_dialog_label.size = Vector2( text_width , text_height )
	_dialog_label.position = Vector2( dialog_text_padding.x / DIALOG_SCALE , dialog_text_padding.y / DIALOG_SCALE )
	_tween = create_tween()
	_tween.tween_property( _dialog_box , "modulate:a" , 1.0 , DIALOG_FADE_TIME )
	pass


#隐藏对话框：淡出后关闭 visible
func _hide_dialog_box() -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property( _dialog_box , "modulate:a" , 0.0 , DIALOG_FADE_TIME )
	_tween.tween_callback( func() -> void: _dialog_box.visible = false )
	pass
