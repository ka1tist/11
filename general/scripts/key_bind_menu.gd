#键位设置面板：标题 + 键位网格 + 恢复默认 + 提示，标题界面与暂停菜单共用同一份。
#面板自己负责铺行、改键交互与落盘；外层只需要——显示时调 open()，隐藏时调 close()，
#并接 back_requested 决定「返回」回到哪一层（暂停菜单的键位面板藏在设置界面下，
#所以 Esc 的处理统一放在面板里：改键中只取消改键，否则发信号让外层返回）
class_name KeyBindMenu extends VBoxContainer

#本面板请求返回上一层
signal back_requested

#每个键位动作的显示名，顺序与 SaveManager.CONFIG_INPUT_ACTIONS 一致
const KEY_DISPLAY_NAMES : Dictionary = {
	"left" : "向左" ,
	"right" : "向右" ,
	"up" : "向上" ,
	"down" : "向下" ,
	"attack" : "攻击" ,
	"jump" : "跳跃" ,
	"dash" : "冲刺" ,
	"action" : "互动" ,
	"pause" : "暂停" ,
	"health" : "回血" ,
}

@onready var key_grid: GridContainer = $KeyGrid
@onready var 恢复默认: Button = $恢复默认

#动作名 -> 该行显示/修改键位的按钮
var _key_buttons : Dictionary = {}
#动作名顺序，用于 open() 时聚焦第一行（字典不保证遍历顺序）
var _key_order : Array[ String ] = []
#正在等待玩家按键的动作名；空串表示当前没有处于改键状态
var _rebinding : String = ""


func _ready() -> void:
	_build_key_rows()
	恢复默认.pressed.connect( _on_restore_defaults_pressed )
	pass


#显示本面板前调用：刷新键位文字并把焦点放到第一行，方便直接上下选择
func open() -> void:
	_refresh_key_texts()
	if not _key_order.is_empty():
		( _key_buttons[ _key_order[ 0 ] ] as Button ).grab_focus()
	pass


#隐藏本面板前调用：丢弃未完成的改键状态，否则下次进来还停在「按 任 意 键 …」
func close() -> void:
	_rebinding = ""
	pass


func _input( event : InputEvent ) -> void:
	if _rebinding != "":
		#改键期间吃下所有键盘事件：Esc 取消，其它键写进该动作的绑定。
		#放在 _input 阶段（早于按钮的 _gui_input 与 _unhandled_input），标记已处理，
		#这样同一次按键不会又触发按钮，也不会顺带触发外层的「返回上一层」
		if not ( event is InputEventKey ):
			return
		var key : InputEventKey = event
		if not key.pressed or key.echo:
			return
		get_viewport().set_input_as_handled()
		#两类写法项目里都有：物理键码（方向键）与普通键码（空格/Esc），取非零的那个
		var code : int = key.physical_keycode if key.physical_keycode != 0 else key.keycode
		if code == KEY_ESCAPE:
			_rebinding = ""
			_refresh_key_texts()
			return
		_apply_key_binding( _rebinding , key )
		return
	#未改键时 Esc 返回上一层；只有本面板可见才接管，免得抢了别的界面的返回键
	if not visible:
		return
	if event.is_action_pressed( "ui_cancel" ):
		get_viewport().set_input_as_handled()
		back_requested.emit()
	pass


#按 SaveManager.CONFIG_INPUT_ACTIONS 在 KeyGrid 里铺「名称 Label + 按键 Button」的行
func _build_key_rows() -> void:
	for action in SaveManager.CONFIG_INPUT_ACTIONS:
		if not InputMap.has_action( action ):
			continue
		
		var name_label := Label.new()
		name_label.text = KEY_DISPLAY_NAMES.get( action , action )
		name_label.custom_minimum_size = Vector2( 64 , 0 )
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		key_grid.add_child( name_label )
		
		var key_button := Button.new()
		key_button.custom_minimum_size = Vector2( 112 , 26 )
		key_button.add_theme_font_size_override( "font_size" , 14 )
		key_button.pressed.connect( _on_key_button_pressed.bind( action ) )
		key_grid.add_child( key_button )
		
		_key_buttons[ action ] = key_button
		_key_order.append( action )
	pass


#读取某动作当前的键盘绑定拼成文本（同一动作有多个键时用 / 分隔）
func _key_text( action : String ) -> String:
	var parts : Array[ String ] = []
	for e in InputMap.action_get_events( action ):
		if not ( e is InputEventKey ):
			continue
		var key : InputEventKey = e
		var code : int = key.physical_keycode if key.physical_keycode != 0 else key.keycode
		if code == 0:
			continue
		parts.append( OS.get_keycode_string( code ) )
	if parts.is_empty():
		return "未 绑 定"
	return " / ".join( parts )


func _refresh_key_texts() -> void:
	for action in _key_buttons:
		var btn := _key_buttons[ action ] as Button
		btn.text = _key_text( action )
	pass


func _on_key_button_pressed( action : String ) -> void:
	_rebinding = action
	var btn := _key_buttons[ action ] as Button
	btn.text = "按 任 意 键 …"
	pass


#把新键写进该动作：清掉原有的键盘绑定（保留手柄/摇杆），只留这一个新键。
#InputMap 没有「只删键盘事件」的接口，只能整组清空后再把非键盘的挂回去
func _apply_key_binding( action : String , key : InputEventKey ) -> void:
	var kept : Array[ InputEvent ] = []
	for e in InputMap.action_get_events( action ):
		if not ( e is InputEventKey ):
			kept.append( e )
	InputMap.action_erase_events( action )
	for e in kept:
		InputMap.action_add_event( action , e )
	
	var new_key := InputEventKey.new()
	new_key.physical_keycode = key.physical_keycode
	new_key.keycode = key.keycode
	InputMap.action_add_event( action , new_key )
	#改的是方向键的话，界面导航键同步跟上，否则刚设的键在菜单里没法上下选择按钮
	SaveManager.sync_direction_ui_actions()
	
	_rebinding = ""
	_refresh_key_texts()
	#改键立即落盘到 user://settings.cfg，下次启动由 SaveManager.load_configuration 恢复
	SaveManager.save_configuration()
	pass


#恢复默认：键盘与手柄绑定全部还原为 project.godot 的出厂值，并落盘
func _on_restore_defaults_pressed() -> void:
	_rebinding = ""
	SaveManager.restore_default_input()
	_refresh_key_texts()
	SaveManager.save_configuration()
	pass
