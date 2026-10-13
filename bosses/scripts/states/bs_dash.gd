class_name BSDash extends BossState

## 二阶段冲刺：带残影高速冲向玩家（进入共用冷却），抵达或超时后衔接 attack。

const DASH_AUDIO = preload( "res://bosses/01/audio/dash.wav" )

var timer : float = 0.0
var _dash_dir : int = 1
var _afterimage_time : float = 0.0


func enter() -> void:
	#冲刺即视为一次追击，进入共用冷却
	boss.start_chase_cooldown()
	_dash_dir = boss.dir_to_target()
	boss.face( _dash_dir )
	boss.velocity.y = 0.0
	_afterimage_time = 0.0
	boss.play_animation( "dash" )
	Audio.play_spatial_sound( DASH_AUDIO , boss.global_position )
	timer = 0.0
	pass


func re_enter() -> void:
	pass


func exit() -> void:
	pass


func physics_update( delta : float ) -> void:
	timer += delta
	#冲刺全程以固定间隔生成残影（与玩家下落攻击同款残影）
	_afterimage_time -= delta
	if _afterimage_time <= 0.0:
		_afterimage_time = Boss.AFTERIMAGE_INTERVAL
		boss.spawn_afterimage()

	boss.velocity.x = float( _dash_dir ) * Boss.DASH_SPEED
	boss.apply_gravity( delta )
	boss.move_and_slide()

	#抵达玩家附近或超时后衔接 attack；普通攻击若仍在冷却则回决策等待
	if ( timer > Boss.DASH_MIN_TIME and absf( boss.dx_to_target() ) <= Boss.ATTACK_RANGE * 0.9 ) or timer >= Boss.DASH_MAX_TIME:
		var next_state : BossState = boss.decision_engine.bs_attack if boss.attack_ready() else boss.decision_engine.bs_decide
		state_machine.change_state( next_state )
	pass
