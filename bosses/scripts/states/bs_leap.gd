class_name BSLeap extends BossState

## 三阶段组合技第一步：skill_01 跃至屏幕正上方中心点（开始即进入 10 秒组合技冷却）。
## 位移由本状态持有的 Tween 驱动，期间铺残影；退出时销毁补间。

var timer : float = 0.0
var _afterimage_time : float = 0.0
var _tween : Tween


func enter() -> void:
	#技能组合开始即进入 10 秒内置冷却
	boss.blackboard.skill_next_use_msec = Time.get_ticks_msec() + Boss.SKILL_COOLDOWN_MSEC
	boss.velocity = Vector2.ZERO
	boss.face_towards_target()
	boss.play_animation( "skill_01" )
	VisualEffects.camera_shake( 5.0 , 0.3 )
	if _tween:
		_tween.kill()
	_tween = boss.create_tween()
	_tween.set_trans( Tween.TRANS_CUBIC ).set_ease( Tween.EASE_OUT )
	#略早于 skill_01 播完到位，避免状态切换瞬间把未完成的位移补间销毁
	_tween.tween_property( boss , "global_position" , boss.screen_top_center() , boss.leap_duration() * 0.9 )

	timer = 0.0
	_afterimage_time = 0.0
	pass


func re_enter() -> void:
	pass


func exit() -> void:
	if _tween:
		_tween.kill()
		_tween = null
	pass


func physics_update( delta : float ) -> void:
	timer += delta
	#位置由 Tween 驱动到屏幕正上方中心点，期间铺残影
	_afterimage_time -= delta
	if _afterimage_time <= 0.0:
		_afterimage_time = Boss.AFTERIMAGE_INTERVAL
		boss.spawn_afterimage()
	if timer >= boss.leap_duration():
		state_machine.change_state( boss.decision_engine.bs_skill_charge )
	pass
