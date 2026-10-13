class_name BSAttack extends BossState

## 普通攻击：面向玩家播放 attack 动画，播完回到决策。

const ATTACK_AUDIO = preload( "res://bosses/01/audio/attack.wav" )

var timer : float = 0.0


func enter() -> void:
	#普通攻击进入即开始 1 秒内置冷却
	boss.start_attack_cooldown()
	boss.face_towards_target()
	boss.velocity.x = 0.0
	boss.play_animation( "attack" )
	Audio.play_spatial_sound( ATTACK_AUDIO , boss.global_position )
	timer = 0.0
	pass


func re_enter() -> void:
	pass


func exit() -> void:
	#attack 动画靠 Sprite/Sprite2D:visible 轨道在第 0.7 秒隐藏武器，
	#若被阶段过场（下蹲无敌）或死亡打断，新动画不含该轨道会保留 visible=true，
	#武器残影会一直挂在身上；离开本状态时统一复位
	boss.sprite_weapon.visible = false
	pass


func physics_update( delta : float ) -> void:
	timer += delta
	boss.velocity.x = 0.0
	boss.apply_gravity( delta )
	boss.move_and_slide()
	#普通攻击时长与 attack 动画等长，播完回到决策
	if timer >= boss.anim_length( "attack" ):
		state_machine.change_state( boss.decision_engine.bs_decide )
	pass
