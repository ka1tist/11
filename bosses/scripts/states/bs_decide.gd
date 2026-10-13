class_name BSDecide extends BossState

## 决策枢纽：停留 DECIDE_DELAY 秒后向决策引擎要下一步行为。

var timer : float = 0.0


func enter() -> void:
	boss.play_animation( "idle" )
	timer = 0.0
	pass


func re_enter() -> void:
	pass


func exit() -> void:
	pass


func physics_update( delta : float ) -> void:
	timer += delta
	boss.velocity.x = move_toward( boss.velocity.x , 0.0 , 1600.0 * delta )
	boss.apply_gravity( delta )
	boss.move_and_slide()
	if timer >= Boss.DECIDE_DELAY:
		state_machine.change_state( boss.decision_engine.decide() )
	pass
