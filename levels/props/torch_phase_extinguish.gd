extends Node2D

## 火炬（特殊）：BOSS 进入二阶段（Messages.boss_phase_changed）时熄灭——点燃的火炬隐藏、
## 熄灭贴图显示，并在火炬处播放熄灭音效。
## 一次性触发：熄灭后一直保持熄灭（BOSS 进三阶段时 phase 仍 >= 2，不会重复熄灭、不会重复播音）。
## BOSS 被击败后火焰亮回原位，此后再不会按阶段熄灭。

#熄灭音效
const EXTINGUISH_AUDIO = preload( "res://general/audio/熄灭.wav" )

#点燃状态的火炬（AnimatedSprite2D 实例，火焰粒子与点光源是它的子节点，隐藏它会一并停止绘制）
@onready var lit_torch : AnimatedSprite2D = $"火炬"
#熄灭状态的贴图
@onready var unlit_torch : Sprite2D = $"熄灭"

var _extinguished : bool = false
#BOSS 被击败后置位：火炬已亮回原位，且不再按阶段熄灭
var _restored : bool = false
#场景里本来的颜色，BOSS 被击败后按原样恢复
var _base_modulate : Color = Color.WHITE


func _ready() -> void:
	Messages.boss_phase_changed.connect( _on_boss_phase_changed )
	#BOSS 被击败 → 熄灭的火炬亮回去
	Messages.boss_defeated.connect( _on_boss_defeated )
	#跟着 BOSS 转阶段一起压暗（火炬与场景背景同步变暗），击败后恢复原色
	_base_modulate = modulate
	pass


#BOSS 阶段变化（phase 为变化后的新阶段）：二阶段起熄灭，并按与背景相同的系数整体压暗自身
func _on_boss_phase_changed( phase : int , _phase_name : String ) -> void:
	var a : float = 0.0
	if phase >= 3:
		a = Boss.BACKGROUND_DARKEN_PHASE3
	elif phase >= 2:
		a = Boss.BACKGROUND_DARKEN_PHASE2
	_tween_darken( 1.0 - a )
	if _restored:
		return
	if phase >= 2:
		_extinguish()
	pass


#按系数整体变暗/恢复（modulate 向子节点传播，火炬本体与火焰粒子一起变）
func _tween_darken( k : float ) -> void:
	var target := Color( _base_modulate.r * k , _base_modulate.g * k , _base_modulate.b * k , _base_modulate.a )
	create_tween().tween_property( self , "modulate" , target , Boss.BACKGROUND_DARKEN_TIME )
	pass


#BOSS 被击败：熄灭的火炬亮回原位（点燃的火炬重新显示、熄灭贴图隐藏），
#并停止再按阶段熄灭；本来就是点着的（没熄灭过）则什么都不做
func _on_boss_defeated() -> void:
	_restored = true
	_tween_darken( 1.0 )
	if not _extinguished:
		return
	_extinguished = false
	lit_torch.visible = true
	unlit_torch.visible = false
	Audio.play_spatial_sound( EXTINGUISH_AUDIO , global_position )
	pass


#熄灭：点燃的火炬整体隐藏、熄灭贴图显示，同时在火炬处播放熄灭音效
func _extinguish() -> void:
	if _extinguished:
		return
	_extinguished = true
	lit_torch.visible = false
	unlit_torch.visible = true
	Audio.play_spatial_sound( EXTINGUISH_AUDIO , global_position )
	pass
