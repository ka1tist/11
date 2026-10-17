extends Node2D

## 插地火把（特殊）：玩家进入检测范围时火焰熄灭——点燃的火把隐藏、熄灭火把显示，并播放熄灭音效。
## 一次性触发：熄灭后一直保持熄灭（玩家离开范围也不会重新点燃）。
## BOSS 被击败后火焰亮回原位，并永久关闭「靠近熄灭」特性（此后再进范围也不会熄灭）。

#熄灭音效
const EXTINGUISH_AUDIO = preload( "res://general/audio/熄灭.wav" )

#点燃状态的火把（AnimatedSprite2D 实例，火焰粒子与点光源是它的子节点，隐藏它会一并停止绘制）
@onready var lit_torch : AnimatedSprite2D = $"插地火把"
#熄灭状态的贴图
@onready var unlit_torch : Sprite2D = $"熄灭火把"
#玩家检测范围
@onready var detect_area : Area2D = $Area2D

var _extinguished : bool = false
#BOSS 被击败后置位：火把已亮回原位，且不再触发「靠近熄灭」
var _disabled : bool = false
#场景里本来的颜色，BOSS 被击败后按原样恢复
var _base_modulate : Color = Color.WHITE


func _ready() -> void:
	#BOSS 已被击败（存档持久化标记）：火把保持战后状态——点着的、且不再有「靠近熄灭」特性。
	#这条状态原本由 boss_defeated 信号带来，但 BOSS 已被击败后不会再出现、信号也就不会再来，
	#所以改为直接读存档标记；放在最前面一并跳过下面那次「出生就在范围内」的补检测
	if Boss.is_defeated_recorded():
		_disabled = true
		return
	detect_area.body_entered.connect( _on_body_entered )
	#BOSS 被击败 → 熄灭的火把亮回去，并永久关闭靠近熄灭特性
	Messages.boss_defeated.connect( _on_boss_defeated )
	#跟着 BOSS 转阶段一起压暗（火把与场景背景同步变暗），击败后恢复原色
	_base_modulate = modulate
	Messages.boss_phase_changed.connect( _on_boss_phase_changed )
	#场景加载时玩家可能已经站在范围内（出生点/读档点就在火把旁），一帧物理后补检测一次
	await get_tree().physics_frame
	for body in detect_area.get_overlapping_bodies():
		if body is Player:
			_extinguish()
			break
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


#按系数整体变暗/恢复（modulate 向子节点传播，火把本体与火焰粒子一起变）
func _tween_darken( k : float ) -> void:
	var target := Color( _base_modulate.r * k , _base_modulate.g * k , _base_modulate.b * k , _base_modulate.a )
	create_tween().tween_property( self , "modulate" , target , Boss.BACKGROUND_DARKEN_TIME )
	pass


func _on_body_entered( body : Node2D ) -> void:
	if _disabled:
		return
	if body is Player:
		_extinguish()
	pass


#BOSS 被击败：熄灭的火把亮回原位（点燃的火把重新显示、熄灭贴图隐藏），
#并永久关闭「靠近熄灭」特性；本来就是点着的（没熄灭过）则什么都不做
func _on_boss_defeated() -> void:
	_disabled = true
	_tween_darken( 1.0 )
	if not _extinguished:
		return
	_extinguished = false
	lit_torch.visible = true
	unlit_torch.visible = false
	Audio.play_spatial_sound( EXTINGUISH_AUDIO , global_position )
	pass


#熄灭：点燃的火把整体隐藏、熄灭火把显示，同时在火把处播放熄灭音效
func _extinguish() -> void:
	if _extinguished:
		return
	_extinguished = true
	lit_torch.visible = false
	unlit_torch.visible = true
	Audio.play_spatial_sound( EXTINGUISH_AUDIO , global_position )
	pass
