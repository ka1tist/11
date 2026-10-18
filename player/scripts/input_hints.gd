@icon( "res://general/icons/input_hints.svg" )
class_name InputHint extends Node2D

const HINT_MAP : Dictionary = {
	"keyboard" : {
		"interact" : 12,
		"attack" : 10,
		"jump" : 9,
		"dash" : 11,
		"up" : 13
	},
	"xbox" : {
		"interact" : 8,
		"attack" : 7,
		"jump" : 5,
		"dash" : 6,
		"up" : 4
	},
	"playstation" : {
		"interact" : 0,
		"attack" : 2,
		"jump" : 1,
		"dash" : 3,
		"up" : 4
	},
	"unknown" : {
		"interact" : 8,
		"attack" : 7,
		"jump" : 5,
		"dash" : 6,
		"up" : 4
	},
}

#提示 -> 该提示对应的游戏动作：玩家改过键之后，头上要显示他实际按的键
const HINT_ACTION : Dictionary = {
	"interact" : "action" ,
	"attack" : "attack" ,
	"jump" : "jump" ,
	"dash" : "dash" ,
	"up" : "up" ,
}

#键盘键码 -> 图集帧号。图集里只有这 7 个键帽，其余键用 KeyCap 现画的键帽显示按键名
const KEYBOARD_KEY_FRAMES : Dictionary = {
	KEY_Z : 9 ,
	KEY_X : 10 ,
	KEY_C : 11 ,
	KEY_S : 12 ,
	KEY_UP : 13 ,
	KEY_ESCAPE : 14 ,
	KEY_E : 15 ,
}

#代码键帽的位置与尺寸：中心与 Sprite2D 对齐在同一处（Sprite2D 在 (0,-4)）
const KEYCAP_CENTER : Vector2 = Vector2( 0 , -4 )
const KEYCAP_HEIGHT : float = 22.0
const KEYCAP_MIN_WIDTH : float = 18.0
#左右总留白，与 StyleBoxFlat 的 content_margin_left / right（各 5）对应
const KEYCAP_PADDING_X : float = 10.0


var controller_type : String = "keyboard"


@onready var sprite_2d: Sprite2D = $Sprite2D
@onready var key_cap: Label = $KeyCap


func _ready() -> void:
	visible = false
	Messages.input_hint_changed.connect( _on_hint_changed )
	pass
	

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton or event is InputEventKey:
		controller_type = "keyboard"
	elif event is InputEventJoypadButton:
		get_controller_type( event.device )
	pass


func get_controller_type( device_id : int ) -> void:
	var n : String = Input.get_joy_name( device_id ).to_lower()
	
	if "xbox" in n :
		controller_type = "xbox"
	elif "playstation" in n or "ps" in n or "dualsense" in n :
		controller_type = "playstation"
	else :
		controller_type = "unknown"
		
	set_process_input( false )
	pass




func _on_hint_changed( hint : String ) -> void:
	if hint == "":
		visible = false
		key_cap.visible = false
		return
	visible = true
	#键盘：先看玩家有没有把该提示对应的动作改到别的键上
	if controller_type == "keyboard":
		var rebound : InputEventKey = _rebound_key( hint )
		if rebound != null:
			var code : int = _key_code( rebound )
			if KEYBOARD_KEY_FRAMES.has( code ):
				_show_sprite( KEYBOARD_KEY_FRAMES[ code ] )
			else:
				_show_key_cap( OS.get_keycode_string( code ) )
			return
	#没改键（或手柄）：仍用图集里对应的固定帧
	var map_key := controller_type if HINT_MAP.has(controller_type) else "unknown"
	_show_sprite( HINT_MAP[ map_key ].get( hint , 0 ) )
	pass


#该提示对应的动作若被玩家改过键，返回现在绑定的那个键盘事件；与出厂默认一致则返回 null。
#比的是键盘绑定的集合：只换了手柄/摇杆绑定不算改键
func _rebound_key( hint : String ) -> InputEventKey:
	var action : String = HINT_ACTION.get( hint , "" )
	if action == "" or not InputMap.has_action( action ):
		return null
	
	var current : Array[ int ] = []
	var first : InputEventKey = null
	for e in InputMap.action_get_events( action ):
		if e is InputEventKey:
			current.append( _key_code( e ) )
			if first == null:
				first = e
	
	var defaults : Array[ int ] = []
	var setting : Dictionary = ProjectSettings.get_setting( "input/" + action , {} )
	for e in setting.get( "events" , [] ):
		if e is InputEventKey:
			defaults.append( _key_code( e ) )
	
	current.sort()
	defaults.sort()
	if current == defaults:
		return null
	return first


func _key_code( e : InputEventKey ) -> int:
	#两类写法项目里都有：物理键码（方向键/字母）与普通键码（空格/回车），取非零的那个
	return e.physical_keycode if e.physical_keycode != 0 else e.keycode


func _show_sprite( frame : int ) -> void:
	sprite_2d.visible = true
	sprite_2d.frame = frame
	key_cap.visible = false
	pass


#用代码画的键帽显示按键名：宽度按文字长度撑开，中心保持在 KEYCAP_CENTER。
#输入提示挂在玩家根下（x 被镜像），所以键帽自身 scale.x 取 -1 抵消
func _show_key_cap( key_text : String ) -> void:
	sprite_2d.visible = false
	key_cap.visible = true
	key_cap.text = key_text
	var font : Font = key_cap.get_theme_font( "font" )
	var font_size : int = key_cap.get_theme_font_size( "font_size" )
	var text_width : float = font.get_string_size( key_text , HORIZONTAL_ALIGNMENT_LEFT , -1 , font_size ).x
	var w : float = maxf( KEYCAP_MIN_WIDTH , text_width + KEYCAP_PADDING_X )
	key_cap.size = Vector2( w , KEYCAP_HEIGHT )
	#镜像缩放绕 pivot 进行，所以中心 = position + pivot；反推 position 让中心落在 KEYCAP_CENTER
	key_cap.pivot_offset = key_cap.size * 0.5
	key_cap.position = KEYCAP_CENTER - key_cap.pivot_offset
	pass
