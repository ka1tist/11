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
	#像素爆散特效：与下砸尖刺同一套对齐方式——Sprite2D 以帧中心为原点，把「画面下边缘到帧中心的距离 × 缩放」
	#换算成抬高量（实测第 1 行各帧画面最低到帧内 y=126，距帧中心 126 - 63.5 = 62.5，×0.9 = 56.25），
	#特效最下面正好落在 BOSS 脚底（BOSS 原点即脚底、下蹲时脚底不动），不再埋进地面
	_fx_time -= delta
	if _fx_time <= 0.0:
		_fx_time = 0.12
		VisualEffects.play_effect_row( 1 , boss.global_position + Vector2( 0 , -56.25 ) , 0.9 , false , 10.0 , boss )
	if timer >= Boss.CHARGE_TIME:
		state_machine.change_state( boss.decision_engine.bs_dash )
	pass
