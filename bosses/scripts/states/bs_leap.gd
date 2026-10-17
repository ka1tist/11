class_name BSLeap extends BossState

## 三阶段组合技第一步：skill_01 跃至「屏幕正上方、道具所在 x」处（x 固定取道具位置，见 Boss.slam_target_x）。
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
	#竖直方向照旧取相机可视区上沿之外；水平方向固定取道具位置（见 Boss.slam_target_x），
	#这样玩家贴到竞技场边缘、镜头被限制夹住时，砸地落点也不会跟着偏，永远落在道具上
	var leap_top : Vector2 = boss.screen_top_center()
	leap_top.x = boss.slam_target_x()
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
	#位置由 Tween 驱动到屏幕正上方中心点，期间铺残影
	_afterimage_time -= delta
	if _afterimage_time <= 0.0:
		_afterimage_time = Boss.AFTERIMAGE_INTERVAL
		boss.spawn_afterimage()
	if timer >= boss.leap_duration():
		state_machine.change_state( boss.decision_engine.bs_skill_charge )
	pass
