extends Sprite2D

## 道具：BOSS 进入三阶段前隐藏，进入三阶段后显示（Messages.boss_phase_changed 的 phase >= 3）；
## BOSS 被击败后再隐藏（战斗结束道具消失）。
## 点光源与粒子都是本节点的子节点，可见性随根节点一并切换：隐藏时不发光、不绘制。


func _ready() -> void:
	visible = false
	Messages.boss_phase_changed.connect( _on_boss_phase_changed )
	Messages.boss_defeated.connect( _on_boss_defeated )
	pass


#BOSS 阶段变化（phase 为变化后的新阶段）：三阶段起显示
func _on_boss_phase_changed( phase : int , _phase_name : String ) -> void:
	visible = phase >= 3
	pass


#BOSS 被击败：隐藏（阶段变化回调不会再触发，所以不会与上面的显示逻辑互相打架）
func _on_boss_defeated() -> void:
	visible = false
	pass
