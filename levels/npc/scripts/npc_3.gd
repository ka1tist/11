class_name NPC3 extends NPC1

## 商店 NPC：完全继承 NPC1 的交互区、对话框与对话流程，只在“对话读完最后一段”这一步
## 追加行为——弹出选项面板（商店 / 离开），选「商店」进入 ShopUI 的商店界面。
##
## 中途走开（_on_body_exited）或被房屋隐藏（set_interaction_enabled）触发的 _end_dialog()
## 不会弹出面板，保证 NPC1 原有的对话中断逻辑不变。

var _shop_ui : ShopUI


func _ready() -> void:
	super._ready()
	#商店界面挂在 NPC 下：CanvasLayer 不受父节点变换影响，始终按屏幕坐标显示
	_shop_ui = ShopUI.new()
	add_child( _shop_ui )
	_shop_ui.closed.connect( _on_shop_closed )
	pass


## 覆盖 NPC1：只有在玩家把对话推进到末段之后才打开面板
func _advance_dialog() -> void:
	_dialog_index += 1
	if _dialog_index >= dialog_lines.size():
		_end_dialog()
		_open_shop_ui()
		return
	_show_dialog_line( dialog_lines[ _dialog_index ] )
	pass


func _open_shop_ui() -> void:
	#面板打开期间整棵场景树被暂停，玩家无法移动 / 跳跃 / 再次触发交互，提示一并清空
	Messages.input_hint_changed.emit( "" )
	_shop_ui.open()
	pass


func _on_shop_closed() -> void:
	#关闭面板后玩家仍在交互范围内（暂停期间无法移动），恢复“可交互”提示
	if is_instance_valid( _interaction_area ) and _interaction_area.monitoring:
		Messages.input_hint_changed.emit( "interact" )
	pass
