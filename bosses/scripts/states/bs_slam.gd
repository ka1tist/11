class_name BSSlam extends BossState

## 三阶段组合技第三步：从跃顶点（道具所在处，见 Boss.slam_target_pos）垂直砸向地面，
## 落地触发砸击特效并回到决策。
## 组合技的 10 秒内置冷却在下砸落地这一刻才重新起算（整段组合技期间不再倒计时）。

func enter() -> void:
	boss.face_towards_target()
	boss.play_animation( "dash" )
	#下落开始：技能蓄力的持续音效到此结束
	boss.stop_hold_audio()
	boss.velocity = Vector2( 0.0 , Boss.SLAM_SPEED )
	VisualEffects.camera_shake( 4.0 , 0.2 )
	pass


func re_enter() -> void:
	pass


func exit() -> void:
	pass


func physics_update( _delta : float ) -> void:
	#垂直砸向地面
	boss.velocity.x = 0.0
	boss.velocity.y = Boss.SLAM_SPEED
	boss.move_and_slide()
	if boss.is_on_floor():
		#落地砸击的瞬间才重新起算 10 秒组合技冷却
		boss.blackboard.skill_next_use_msec = Time.get_ticks_msec() + Boss.SKILL_COOLDOWN_MSEC
		boss.slam_impact()
		state_machine.change_state( boss.decision_engine.bs_decide )
	pass
