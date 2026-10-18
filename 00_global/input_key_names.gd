class_name InputKeyNames
extends RefCounted

#把 InputMap 里的键位翻译成给玩家看的按键名（提示牌、能力球说明等文案用）。
#写成静态函数而不挂自动加载：@tool 脚本在编辑器里也会执行（编辑器里没有 SaveManager 节点），
#静态调用在编辑器和运行时的行为一致，摆在场景里就能预览到默认键位

#方向键在文案里画成箭头，其余按键用系统给出的按键名（如 K、Space）
const NAME_OVERRIDES : Dictionary = {
	KEY_UP : "↑" ,
	KEY_DOWN : "↓" ,
	KEY_LEFT : "←" ,
	KEY_RIGHT : "→" ,
	KEY_SPACE : "空格" ,
	KEY_ESCAPE : "Esc" ,
}


#某动作当前绑定的第一个键盘键的显示名；同一动作有多个键时（如跳跃是 z + 空格）只取第一个
static func action_key_name( action : String ) -> String:
	if not InputMap.has_action( action ):
		return "—"
	for e in InputMap.action_get_events( action ):
		if not ( e is InputEventKey ):
			continue
		var key : InputEventKey = e
		var code : int = key.physical_keycode if key.physical_keycode != 0 else key.keycode
		if code != 0:
			return key_name( code )
	return "—"


#键码 -> 显示名
static func key_name( code : int ) -> String:
	if NAME_OVERRIDES.has( code ):
		return str( NAME_OVERRIDES[ code ] )
	var text : String = OS.get_keycode_string( code )
	#单个字母统一小写，与项目里写死的 x / z / c 写法一致
	return text.to_lower() if text.length() == 1 else text
