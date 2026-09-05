class_name TutorialSign extends Node2D

#靠近时显示的文本内容，可在编辑器中按实例修改
@export_multiline var text : String = "操作提示"
#检测范围大小
@export var detect_size : Vector2 = Vector2( 56 , 64 )

@onready var area_2d: Area2D = $Area2D
@onready var collision_shape: CollisionShape2D = $Area2D/CollisionShape2D
@onready var text_box: PanelContainer = $TextBox
@onready var text_label: Label = $TextBox/MarginContainer/Label

var _tween : Tween


func _ready() -> void:
	text_label.text = text
	( collision_shape.shape as RectangleShape2D ).size = detect_size
	text_box.visible = false
	area_2d.body_entered.connect( _on_body_entered )
	area_2d.body_exited.connect( _on_body_exited )
	#场景加载时若玩家已在范围内（如切换场景出生点附近），一帧物理后也直接显示
	await get_tree().physics_frame
	for body in area_2d.get_overlapping_bodies():
		if body is Player:
			_show_text_box()
			break
	pass


func _on_body_entered( body : Node2D ) -> void:
	if body is Player:
		_show_text_box()
	pass


func _on_body_exited( body : Node2D ) -> void:
	if body is Player:
		_hide_text_box()
	pass


func _show_text_box() -> void:
	if text_box.visible:
		return
	text_box.visible = true
	if _tween:
		_tween.kill()
	_tween = create_tween()
	text_box.modulate.a = 0.0
	_tween.tween_property( text_box , "modulate:a" , 1.0 , 0.15 )
	pass


func _hide_text_box() -> void:
	if not text_box.visible:
		return
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property( text_box , "modulate:a" , 0.0 , 0.15 )
	_tween.tween_callback( func() -> void: text_box.visible = false )
	pass
