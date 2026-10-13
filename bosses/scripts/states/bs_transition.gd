class_name BSTransition extends BossState

## 阶段过场：crouch 下蹲 + 无敌 + 持续震屏，期间保持朝向玩家（锁定不丢失），
## 并关闭贴身碰撞伤害（过场结束再打开）。

var timer : float = 0.0


func enter() -> void:
	boss.blackboard.invulnerable = true
	boss.set_damage_invulnerable( true )
	#过场期间关闭贴身碰撞伤害，避免玩家在无敌演出里白白挨打
	boss.set_contact_damage( false )
	boss.velocity.x = 0.0
	timer = 0.0
	boss.play_animation( "crouch" )
	#切阶段时背景整体加深：二阶段轻微、三阶段在此基础上再加深
	boss.apply_phase_background( boss.blackboard.phase )
	#过场配套增强：强力震屏 + HUD 横幅/闪光（由 boss_phase_changed 驱动）
	VisualEffects.camera_shake( 8.0 , 0.5 )
	Messages.boss_phase_changed.emit( boss.blackboard.phase , boss.phase_display_name() )
	pass


func re_enter() -> void:
	pass


func exit() -> void:
	#阶段过场结束：解除无敌（死亡时保持无敌）
	if not boss.blackboard.dead:
		boss.blackboard.invulnerable = false
		boss.set_damage_invulnerable( false )
		#过场结束：恢复贴身碰撞伤害
		boss.set_contact_damage( true )
	pass


func physics_update( delta : float ) -> void:
	timer += delta
	boss.velocity.x = 0.0
	boss.apply_gravity( delta )
	boss.move_and_slide()
	#过场期间依然朝向玩家，保证锁定关系不丢失
	if boss.has_target():
		boss.face( boss.dir_to_target() )

	VisualEffects.camera_shake( 4.0 , 0.12 )

	if timer >= Boss.TRANSITION_TIME[ clampi( boss.blackboard.phase , 0 , Boss.MAX_PHASE ) ]:
		state_machine.change_state( boss.decision_engine.bs_decide )
	pass
