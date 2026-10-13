class_name BSDeath extends BossState

## 死亡：death 动画 → 广播 boss_defeated → 精灵与武器同步淡出 → 销毁整只 BOSS。

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
	Messages.boss_defeated.emit()
	#死亡掉落：在倒下的地方留下冲刺能力球（必须在 BOSS 销毁前生成到世界节点下）
	#本状态是由受击信号（AttackArea 的 body_entered）触发进入的，此刻物理服务器正在派发查询信号，
	#此时往场景里挂带判定形状的能力球会被拒绝（Can't change this state while flushing queries），故延后一帧
	boss.spawn_dash_pickup.call_deferred()
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
	boss.queue_free()
	pass
