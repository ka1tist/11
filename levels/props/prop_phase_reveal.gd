extends Sprite2D

## 道具：BOSS 进入三阶段前隐藏，进入三阶段后显示（Messages.boss_phase_changed 的 phase >= 3）；
## BOSS 被击败后再隐藏（战斗结束道具消失）。
## 点光源与粒子都是本节点的子节点，可见性随根节点一并切换：隐藏时不发光、不绘制。

#预热时使用的不透明度：肉眼几乎看不见，但仍在引擎的绘制裁切阈值之上，能被真正提交绘制
const WARM_UP_ALPHA : float = 0.01


func _ready() -> void:
	visible = false
	Messages.boss_phase_changed.connect( _on_boss_phase_changed )
	Messages.boss_defeated.connect( _on_boss_defeated )
	_warm_up()
	pass


#预热（只影响首帧性能，不改玩法）：本道具三阶段前一直隐藏，它自带的点光源与 GPU 粒子
#（含湍流噪声、unshaded 材质变体）都是「三阶段第一次显示」时才首次绘制，引擎要现编着色器，
#表现为第一次运行时在此处掉一小段帧（第二次运行有 shader cache 就不卡了）。
#这里趁关卡刚加载、玩家还在黑场淡入时，把整棵子树搬到镜头处以 1% 不透明度画两帧，
#把这些一次性开销提前做掉。点光源预热期间暂时关掉，避免贴着镜头亮一下。
func _warm_up() -> void:
	#玩家由 PlayerSpawn 在下一帧才生成，先等两帧才有相机可以对齐
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree():
		return
	var base_position : Vector2 = global_position
	var base_modulate : Color = modulate
	var light := get_node_or_null( "PointLight2D" ) as PointLight2D
	var light_visible : bool = light.visible if light != null else false
	if light != null:
		light.visible = false
	#粒子只有真的被画出来才会编译绘制管线：预热时先把粒子预演 1 秒并重启，
	#保证第一帧就有粒子存在；预热结束后只把 preprocess 还原（不重启），
	#粒子照旧从加载起持续发射，三阶段显示时的状态与原来一致
	var particles := get_node_or_null( "GPUParticles2D" ) as GPUParticles2D
	var base_preprocess : float = particles.preprocess if particles != null else 0.0
	if particles != null:
		particles.preprocess = 1.0
		particles.restart()
	#道具一般不在开场镜头里：画面外的节点会被裁掉、根本画不到，起不到预热作用，
	#所以临时挪到相机处（1% 不透明度看不出位置变化）
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		global_position = cam.global_position
	modulate = Color( base_modulate.r , base_modulate.g , base_modulate.b , WARM_UP_ALPHA )
	visible = true
	await get_tree().process_frame
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if not is_inside_tree():
		return
	#恢复原状：三阶段前保持隐藏，位置/颜色/光源可见性都还原
	visible = false
	modulate = base_modulate
	global_position = base_position
	if light != null:
		light.visible = light_visible
	if particles != null:
		particles.preprocess = base_preprocess
	pass


#BOSS 阶段变化（phase 为变化后的新阶段）：三阶段起显示
func _on_boss_phase_changed( phase : int , _phase_name : String ) -> void:
	visible = phase >= 3
	pass


#BOSS 被击败：隐藏（阶段变化回调不会再触发，所以不会与上面的显示逻辑互相打架）
func _on_boss_defeated() -> void:
	visible = false
	pass
