class_name BSJump extends BossState

## 一阶段追击：跳跃贴近玩家（进入共用冷却）。落地后够近接普攻，否则回决策。

var timer : float = 0.0


func enter() -> void:
	#跳跃即视为一次追击，进入共用冷却
	boss.start_chase_cooldown()
	boss.play_animation( "jump" )
	boss.velocity = Vector2( float( boss.dir_to_target() ) * Boss.JUMP_SPEED_X , -Boss.JUMP_FORCE )
	timer = 0.0
	pass


func re_enter() -> void:
	pass


func exit() -> void:
	pass


func physics_update( delta : float ) -> void:
	timer += delta
	var dir : int = boss.dir_to_target()
	boss.face( dir )
	boss.velocity.x = float( dir ) * Boss.JUMP_SPEED_X
	boss.velocity.y = minf( boss.velocity.y + Boss.GRAVITY * delta , Boss.MAX_FALL_SPEED )
	boss.move_and_slide()
	#落地且已离地一小段时间后重新决策（足够近且普攻已过冷却则直接接普攻）
	if timer > Boss.JUMP_GRACE and boss.is_on_floor():
		if absf( boss.dx_to_target() ) <= Boss.ATTACK_RANGE and boss.attack_ready():
			state_machine.change_state( boss.decision_engine.bs_attack )
		else:
			state_machine.change_state( boss.decision_engine.bs_decide )
	pass
