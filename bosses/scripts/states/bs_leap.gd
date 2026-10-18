class_name BSLeap extends BossState

## 三阶段组合技第一步：skill_01 跃至「关卡里道具（props/道具，三阶段点亮的太阳）所在处」，
## 竖直方向也取道具位置（见 Boss.slam_target_pos），BOSS 就停在道具上而不是屏幕正上方。
## 位移由本状态持有的 Tween 驱动，期间铺残影；退出时销毁补间。
## 组合技冷却不在这里起算，而是等最后一步下砸落地后才重新计时（见 bs_slam.gd）。

var timer : float = 0.0
var _afterimage_time : float = 0.0
var _tween : Tween


func enter() -> void:
	boss.velocity = Vector2.ZERO
	boss.face_towards_target()
	boss.play_animation( "skill_01" )
	VisualEffects.camera_shake( 5.0 , 0.3 )
	if _tween:
		_tween.kill()
	_tween = boss.create_tween()
	_tween.set_trans( Tween.TRANS_CUBIC ).set_ease( Tween.EASE_OUT )
	#跃顶点直接取关卡里道具（三阶段点亮的太阳）的位置：道具就是给玩家看的落点标记，
	#落点也必须落在它上面（解析不到道具时 slam_target_pos 退回屏幕正上方那套）
	var leap_top : Vector2 = boss.slam_target_pos()
	#略早于 skill_01 播完到位，避免状态切换瞬间把未完成的位移补间销毁
	_tween.tween_property( boss , "global_position" , leap_top , boss.leap_duration() * 0.9 )

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
	#位置由 Tween 驱动到道具所在处（跃顶点），期间铺残影
	_afterimage_time -= delta
	if _afterimage_time <= 0.0:
		_afterimage_time = Boss.AFTERIMAGE_INTERVAL
		boss.spawn_afterimage()
	if timer >= boss.leap_duration():
		state_machine.change_state( boss.decision_engine.bs_skill_charge )
	pass
