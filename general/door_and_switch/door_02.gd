@tool
@icon( "res://general/icons/door.svg" )
class_name Door02 extends Node2D


const DOOR_CRASH_AUDIO = preload( "uid://dhjvfy555i040" )


@onready var animation_player: AnimationPlayer = $AnimationPlayer

#场景里本来的颜色，BOSS 被击败后按原样恢复
var _base_modulate : Color = Color.WHITE


func _ready() -> void:
	if Engine.is_editor_hint():
		return
		
	#玩家与 BOSS 交互（唤醒）→ 关门；BOSS 被击败 → 开门并保持打开
	Messages.boss_awakened.connect( _on_boss_awakened )
	Messages.boss_defeated.connect( _on_boss_defeated )
	#跟着 BOSS 转阶段一起压暗（门与场景背景同步变暗），击败后恢复原色
	_base_modulate = modulate
	Messages.boss_phase_changed.connect( _on_boss_phase_changed )
	pass


#BOSS 阶段变化：按与背景相同的系数整体压暗自身
func _on_boss_phase_changed( phase : int , _phase_name : String ) -> void:
	var a : float = 0.0
	if phase >= 3:
		a = Boss.BACKGROUND_DARKEN_PHASE3
	elif phase >= 2:
		a = Boss.BACKGROUND_DARKEN_PHASE2
	_tween_darken( 1.0 - a )
	pass


#按系数整体变暗/恢复（modulate 向子节点传播，门的贴图与门框一起变）
func _tween_darken( k : float ) -> void:
	var target := Color( _base_modulate.r * k , _base_modulate.g * k , _base_modulate.b * k , _base_modulate.a )
	create_tween().tween_property( self , "modulate" , target , Boss.BACKGROUND_DARKEN_TIME )
	pass


#玩家按下交互键唤醒 BOSS 的瞬间立即关门；动画结束后停在 closed 姿势，碰撞体堵住通道
func _on_boss_awakened() -> void:
	Audio.play_spatial_sound( DOOR_CRASH_AUDIO , global_position )
	animation_player.play( "close" )
	await animation_player.animation_finished
	animation_player.play( "closed" )
	pass
	

#BOSS 被击败后开门；动画结束后停在 opened 姿势并保持打开
func _on_boss_defeated() -> void:
	_tween_darken( 1.0 )
	animation_player.play( "open" )
	await animation_player.animation_finished
	animation_player.play( "opened" )
	pass
