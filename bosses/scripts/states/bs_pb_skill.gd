class_name BSPbSkill extends BossState

## 二/三阶段专属技能：贴近玩家打满 PB_ATTACK_COUNT 次普通攻击后触发
## （由 Boss.update_pb_skill_readiness() 直接进入，不经决策引擎的 decide()）。
## 第一阶段：hurt 受击后撤，带与 dash 同款的残影拉开与玩家的距离；
## 第二阶段：播放 attack_2 并同时沿面朝方向水平发射 pb 投射物，动画结束后回到决策。

#技能内部两段：先后撤、再投掷
enum Phase { RETREAT , THROW }

var phase : int = Phase.RETREAT
#当前阶段的已用时（秒）
var _phase_time : float = 0.0
var _retreat_dir : int = 1
var _afterimage_time : float = 0.0


func enter() -> void:
	#受击瞬间仍面向玩家，后撤方向取其反向
	boss.face_towards_target()
	_retreat_dir = -boss.dir_to_target()
	boss.play_animation( "hurt" )
	phase = Phase.RETREAT
	_phase_time = 0.0
	_afterimage_time = 0.0
	pass


func re_enter() -> void:
	pass


func exit() -> void:
	#解锁：技能结束后才允许在二阶段重新攒够停留时间再次触发
	blackboard.pb_skill_locked = false
	pass


func physics_update( delta : float ) -> void:
	_phase_time += delta
	boss.apply_gravity( delta )

	match phase:
		Phase.RETREAT:
			boss.velocity.x = float( _retreat_dir ) * Boss.HURT_RETREAT_SPEED
			boss.move_and_slide()
			#急退途中铺残影，与 dash 同款（0.05 秒一张）
			_afterimage_time -= delta
			if _afterimage_time <= 0.0:
				_afterimage_time = Boss.AFTERIMAGE_INTERVAL
				boss.spawn_afterimage()
			if _phase_time >= Boss.HURT_RETREAT_TIME:
				_start_throw()
		Phase.THROW:
			boss.velocity.x = 0.0
			boss.move_and_slide()
			#等 attack_2 播完再交回决策，保证动作衔接完整
			if _phase_time >= boss.anim_length( "attack_2" ):
				state_machine.change_state( boss.decision_engine.bs_decide )
	pass


#后撤结束：重新对准玩家，播放 attack_2，并同时发射 pb 投射物
func _start_throw() -> void:
	phase = Phase.THROW
	_phase_time = 0.0
	boss.face_towards_target()
	boss.play_animation( "attack_2" )
	boss.spawn_pb()
	pass
