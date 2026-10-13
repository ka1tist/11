class_name BSSkillCharge extends BossState

## 三阶段组合技第二步：悬停蓄力 SKILL_CHARGE_TIME 秒，散发能量粒子（与二阶段蓄力同款）并逐步增强震屏。
## 蓄力音效 charge.wav 实测仅 0.798 秒，靠按素材长度重播填满整个蓄力过程，进入下落（bs_slam）时才停止。

const CHARGE_AUDIO = preload( "res://bosses/01/audio/charge.wav" )
#重播间隔取素材时长再略提前一点，避免出现空隙
const CHARGE_AUDIO_INTERVAL : float = 0.75

var timer : float = 0.0
var _fx_time : float = 0.0
var _audio_time : float = 0.0


func enter() -> void:
	boss.velocity = Vector2.ZERO
	boss.play_animation( "skill_02" )
	#直接传资源本体：导入 wav 的采样数据在 .godot/imported/*.sample 里，duplicate() 的副本取不到数据会静音
	boss.play_hold_audio( CHARGE_AUDIO )
	timer = 0.0
	_fx_time = 0.0
	_audio_time = CHARGE_AUDIO_INTERVAL
	VisualEffects.camera_shake( 3.0 , 0.3 )
	pass


func re_enter() -> void:
	pass


func exit() -> void:
	pass


func physics_update( delta : float ) -> void:
	timer += delta
	#悬停蓄力：不移动，散发能量粒子（粒子类型与二阶段蓄力同款，偏移取站立姿态的身体中心）并逐步增强震屏
	boss.velocity = Vector2.ZERO
	_fx_time -= delta
	if _fx_time <= 0.0:
		_fx_time = 0.12
		VisualEffects.play_effect_row( 1 , boss.global_position + Vector2( 0 , -60 ) , 0.9 , false , 10.0 )
	#音效素材（0.8 秒）短于蓄力时长（2 秒），按素材长度重播以持续到下落
	_audio_time -= delta
	if _audio_time <= 0.0:
		_audio_time = CHARGE_AUDIO_INTERVAL
		boss.replay_hold_audio()
	VisualEffects.camera_shake( 2.0 + 4.0 * clampf( timer / Boss.SKILL_CHARGE_TIME , 0.0 , 1.0 ) , 0.2 )
	if timer >= Boss.SKILL_CHARGE_TIME:
		state_machine.change_state( boss.decision_engine.bs_slam )
	pass
