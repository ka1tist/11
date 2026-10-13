class_name BSRun extends BossState

## 追击兜底：jump / dash 冷却期间以 run 持续贴近玩家。
## 进入攻击距离直接开打；追击手段或组合技重新就绪则交回决策。

var timer : float = 0.0


func enter() -> void:
	boss.play_animation( "run" )
	timer = 0.0
	pass


func re_enter() -> void:
	pass


func exit() -> void:
	pass


func physics_update( delta : float ) -> void:
	timer += delta
	var dir : int = boss.dir_to_target()
	boss.face( dir )
	boss.velocity.x = float( dir ) * Boss.RUN_SPEED
	boss.apply_gravity( delta )
	boss.move_and_slide()

	#起步缓冲，避免刚进入就立刻跳出
	if timer < Boss.RUN_MIN_TIME:
		return
	#已进入攻击距离且普通攻击已过内置冷却 → 直接开打
	if absf( boss.dx_to_target() ) <= Boss.ATTACK_RANGE and boss.attack_ready():
		state_machine.change_state( boss.decision_engine.bs_attack )
		return
	#追击手段或组合技重新就绪 → 交回决策，改用 jump / dash / 组合技
	if boss.chase_ready() or ( boss.blackboard.phase >= Boss.MAX_PHASE and boss.skill_ready() ):
		state_machine.change_state( boss.decision_engine.bs_decide )
	pass
