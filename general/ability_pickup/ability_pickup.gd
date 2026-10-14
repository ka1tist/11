@tool
@icon( "res://general/icons/ability_pickup.svg" )
class_name AbilityPickup extends Node2D


enum Type { DASH , DOUBLE_JUMP , GROUND_SLAM , WALL_CLIMB }
@export var type : Type = Type.DOUBLE_JUMP :
	set ( value ):
		type = value
		_set_animation()


@onready var ability_anim: AnimationPlayer = %AbilityAnim
@onready var orb_anim: AnimationPlayer = %OrbAnim
@onready var breakable: Breakable = $Breakable
@onready var orb_sprite: Sprite2D = %OrbSprite
#靠近时显示的能力说明（与关卡里的「操作」提示牌同样的机制）
@onready var hint_area: Area2D = $HintArea
@onready var hint_box: PanelContainer = $HintBox
@onready var hint_label: Label = $HintBox/MarginContainer/Label

#提示牌淡入淡出补间
var _hint_tween : Tween




func _ready() -> void:
	_set_animation()
	hint_label.text = get_hint_text()
	
	if Engine.is_editor_hint():
		return
	
	if SaveManager.persistent_data.get_or_add( get_ability_name() , "" ) == "acquired":
		queue_free()
		return
	
	breakable.destroyed.connect( _on_destroyed )
	breakable.damage_taken.connect( _on_damage_taken )
	_setup_hint_area()
	pass


func _on_destroyed() -> void:
	SaveManager.persistent_data[ get_ability_name() ] = "acquired"
	_reward_ability()
	# 保存能力进度（保留存档点位置），确保死亡重生后能力不丢失
	SaveManager.save_progress()
	orb_anim.play( "destroy" )
	await orb_anim.animation_finished
	queue_free()
	pass


func _on_damage_taken() -> void:
	orb_sprite.frame += 1
	pass


#玩家进入范围显示能力说明、离开隐藏（淡入淡出与关卡里的「操作」提示牌一致）
func _setup_hint_area() -> void:
	hint_area.body_entered.connect( _on_hint_body_entered )
	hint_area.body_exited.connect( _on_hint_body_exited )
	#场景加载时玩家已在范围内（例如击破 BOSS 后掉落的能力球本就落在玩家脚下），一帧物理后补一次检测
	await get_tree().physics_frame
	if is_queued_for_deletion():
		return
	for body in hint_area.get_overlapping_bodies():
		if body is Player:
			_show_hint()
			break
	pass


func _on_hint_body_entered( body : Node2D ) -> void:
	if body is Player:
		_show_hint()
	pass


func _on_hint_body_exited( body : Node2D ) -> void:
	if body is Player:
		_hide_hint()
	pass


func _show_hint() -> void:
	if hint_box.visible:
		return
	hint_box.visible = true
	if _hint_tween:
		_hint_tween.kill()
	_hint_tween = create_tween()
	hint_box.modulate.a = 0.0
	_hint_tween.tween_property( hint_box , "modulate:a" , 1.0 , 0.15 )
	pass


func _hide_hint() -> void:
	if not hint_box.visible:
		return
	if _hint_tween:
		_hint_tween.kill()
	_hint_tween = create_tween()
	_hint_tween.tween_property( hint_box , "modulate:a" , 0.0 , 0.15 )
	_hint_tween.tween_callback( func() -> void: hint_box.visible = false )
	pass


func _reward_ability() -> void:
	var player : Player = get_tree().get_first_node_in_group( "Player" )
	match type:
		Type.DOUBLE_JUMP:
			player.double_jump = true
		Type.DASH:
			player.dash = true
		Type.GROUND_SLAM:
			player.ground_slam = true
		Type.WALL_CLIMB:
			player.wall_climb = true
	pass





func _set_animation() -> void:
	#场景反序列化/检查器赋值时type的setter先于_ready触发，此时节点尚未进入场景树，
	#%唯一节点无法解析（会报Node not found），直接跳过；_ready()中会再设置一次
	if not is_inside_tree():
		return
	if not ability_anim:
		if not has_node( "%AbilityAnim" ):
			return
		ability_anim = %AbilityAnim
	ability_anim.play( get_ability_name() )
	pass


func get_ability_name() -> String:
	match type:
		Type.DOUBLE_JUMP:
			return "double_jump"
		Type.DASH:
			return "dash"
		Type.GROUND_SLAM:
			return "ground_slam"
		Type.WALL_CLIMB:
			return "wall_climb"
	return""


#靠近时显示的能力说明文案（按能力类型区分）
func get_hint_text() -> String:
	match type:
		Type.DOUBLE_JUMP:
			return "当玩家获得此能力时可在空中进行二段跳跃"
		Type.DASH:
			return "当玩家获得此能力时按c可进行闪避"
		Type.GROUND_SLAM:
			return "当玩家获得此能力时可以按↓+x进行下砸"
		Type.WALL_CLIMB:
			return "当玩家获得此能力时贴近墙面可以进行爬墙"
	return ""
