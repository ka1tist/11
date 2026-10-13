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
	VisualEffects.camera_shake( 10.0 , 0.6 )
	Messages.boss_defeated.emit()
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
