class_name BSDeath extends BossState

## 死亡：death 动画 → 广播 boss_defeated → 精灵与武器同步淡出 → 等慢动作演出结束 → 掉落能力球 → 销毁整只 BOSS。

#击败聚焦慢动作演出的结束时刻（Time.get_ticks_msec 墙钟）：能力球掉落与本体销毁都要等它
var _focus_end_ms : int = 0

func enter() -> void:
	boss.blackboard.dead = true
	boss.blackboard.invulnerable = true
	boss.velocity = Vector2.ZERO
	boss.clear_hurt_tween()
	boss.sprite.modulate = Color.WHITE
	#死亡瞬间立即切断普攻判定区与贴身碰撞判定（须延迟设置，见 Boss.stop_damage_output）
	boss.stop_damage_output()
	#蓄力途中被打死时停掉持续音效，避免死亡演出期间还在循环
	boss.stop_hold_audio()
	boss.set_damage_invulnerable( true )
	boss.play_animation( "death" )
	#击败 BOSS 后背景恢复原样（传入 1 阶段即无加深，补间回 0）
	boss.apply_phase_background( 1 )
	VisualEffects.camera_shake( 10.0 , 0.6 )
	#击败演出：镜头聚焦锁定到 BOSS 倒下的位置（精灵中心即它的视觉中心）+ 全局 2 秒慢动作 +
	#暗角/身后光晕。必须排在下面 boss_defeated 之前——HUD 的横幅/计时是按当前 time_scale 反向补偿的，
	#慢动作先落下 HUD 才不会被拉长 4 倍。内部有"只触发一次"的守卫，重复进入本状态不会二次触发
	VisualEffects.boss_defeat_focus( boss.sprite.global_position , boss )
	Messages.boss_defeated.emit()
	#广播被击败：BOSS 上挂载的 lootDropper 监听 was_killed 结算掉落（与小怪一致）
	boss.was_killed.emit()
	#聚焦演出结束的时刻：掉落能力球与销毁本体都要等它，保证球一定出现在慢动作之后。
	#时长取自 VisualEffects 的同一组常量（慢动作 2s + 时间缩放恢复 0.5s，都是真实秒数）
	_focus_end_ms = Time.get_ticks_msec() + int( ( VisualEffects.DEFEAT_FOCUS_HOLD + VisualEffects.DEFEAT_FOCUS_RESTORE ) * 1000.0 )
	_death_sequence()
	pass


func re_enter() -> void:
	pass


func exit() -> void:
	pass


func physics_update( _delta : float ) -> void:
	pass


func _death_sequence() -> void:
	await boss.animation_player.animation_finished
	var tw := boss.create_tween()
	tw.set_parallel( true )
	tw.tween_property( boss.sprite , "modulate:a" , 0.0 , 0.5 )
	tw.tween_property( boss.sprite_weapon , "modulate:a" , 0.0 , 0.5 )
	await tw.finished
	#等聚焦慢动作彻底走完再落球：慢动作期间落球会被 0.25 倍速拖住、几乎看不清，
	#掉落要落在「演出收尾、玩家刚拿回操作权」那一拍上。计时用真实秒数（ignore_time_scale），
	#否则 create_timer( 1.0 ) 在慢动作里会变成 4 秒墙钟
	var remain_ms : int = _focus_end_ms - Time.get_ticks_msec()
	if remain_ms > 0:
		await get_tree().create_timer( float( remain_ms ) / 1000.0 , true , false , true ).timeout
	if not is_instance_valid( boss ):
		return
	#死亡掉落：在倒下的地方留下冲刺能力球（此刻 BOSS 本体还在，落点仍能定位到它脚下）
	#进入本状态的当帧落球会被物理服务器拒绝（Can't change this state while flushing queries，
	#带判定形状的节点不能在派发查询信号期间入树），推迟到演出结束早已脱离那次派发，无需再延后帧
	boss.spawn_dash_pickup()
	boss.queue_free()
	pass
