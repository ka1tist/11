class_name BSIdle extends BossState

## 待机：无锁定玩家时使用。原地缓慢刹停 + 重力，不做任何攻击行为。

func enter() -> void:
	boss.velocity = Vector2.ZERO
	boss.play_animation( "idle" )
	pass


#重复进入（无目标时 decide() 每帧仍返回待机）不再重播动画，保持 idle 循环不中断
func re_enter() -> void:
	pass


func exit() -> void:
	pass


func physics_update( delta : float ) -> void:
	boss.velocity.x = move_toward( boss.velocity.x , 0.0 , 1600.0 * delta )
	boss.apply_gravity( delta )
	boss.move_and_slide()
	pass
