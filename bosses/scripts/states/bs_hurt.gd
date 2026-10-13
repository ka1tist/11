class_name BSHurt extends BossState

## 受击退避：1 秒内被玩家连砍两刀时触发（由 Boss._on_damage_taken 直接进入）。
## 播放 hurt 动画（姿态保持），同时向背离玩家的方向急退，途中铺与 dash 同款的残影。

var timer : float = 0.0
var _retreat_dir : int = 1
var _afterimage_time : float = 0.0


func enter() -> void:
	#受击瞬间仍面向玩家，退避方向取其反向
	boss.face_towards_target()
	_retreat_dir = -boss.dir_to_target()
	boss.play_animation( "hurt" )
	timer = 0.0
	_afterimage_time = 0.0
	pass


func re_enter() -> void:
	pass


func exit() -> void:
	pass


func physics_update( delta : float ) -> void:
	timer += delta
	boss.velocity.x = float( _retreat_dir ) * Boss.HURT_RETREAT_SPEED
	boss.apply_gravity( delta )
	boss.move_and_slide()
	#急退途中铺残影，与二阶段 dash 同款（0.05 秒一张）
	_afterimage_time -= delta
	if _afterimage_time <= 0.0:
		_afterimage_time = Boss.AFTERIMAGE_INTERVAL
		boss.spawn_afterimage()
	if timer >= Boss.HURT_RETREAT_TIME:
		state_machine.change_state( boss.decision_engine.bs_decide )
	pass
