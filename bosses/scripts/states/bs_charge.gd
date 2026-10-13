class_name BSCharge extends BossState

## 二阶段蓄力：下蹲 CHARGE_TIME 秒、自身颜色明暗循环并散发能量粒子，随后进入 dash。

const CHARGE_AUDIO = preload( "res://bosses/01/audio/charge.wav" )

var timer : float = 0.0
var _fx_time : float = 0.0


func enter() -> void:
	boss.velocity = Vector2.ZERO
	boss.play_animation( "crouch" )
	#蓄力表现：自身颜色开始明暗循环
	boss.start_charge_flash()
	Audio.play_spatial_sound( CHARGE_AUDIO , boss.global_position )
	timer = 0.0
	_fx_time = 0.0
	pass


func re_enter() -> void:
	pass


func exit() -> void:
	#蓄力结束：颜色恢复
	boss.stop_charge_flash()
	pass


func physics_update( delta : float ) -> void:
	timer += delta
	boss.velocity.x = 0.0
	boss.apply_gravity( delta )
	boss.move_and_slide()
	#蓄力期间散发能量粒子
	_fx_time -= delta
	if _fx_time <= 0.0:
		_fx_time = 0.12
		VisualEffects.play_effect_row( 1 , boss.global_position + Vector2( 0 , -40 ) , 0.9 , false , 10.0 )
	if timer >= Boss.CHARGE_TIME:
		state_machine.change_state( boss.decision_engine.bs_dash )
	pass
