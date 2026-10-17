class_name BSJump extends BossState

## 一阶段追击：跳跃贴近玩家（进入共用冷却）。落地后够近接普攻，否则回决策。
## 跳跃方向在起跳瞬间锁定（见 _jump_dir）：整段轨迹与落点只由起跳时的方向与力度决定，
## 空中不再重取玩家坐标做落点修正，因此玩家在起跳后水平移动也不会把 BOSS 带偏。

var timer : float = 0.0
#起跳瞬间锁定的水平方向（-1 左 / 1 右）：决定整段跳跃的轨迹与落点，空中不再重算
var _jump_dir : int = 1


func enter() -> void:
	#跳跃即视为一次追击，进入共用冷却
	boss.start_chase_cooldown()
	boss.play_animation( "jump" )
	#方向只在这一刻取一次：朝玩家起跳，之后玩家怎么移动都不再影响轨迹，朝向也一并锁定
	_jump_dir = boss.dir_to_target()
	boss.face( _jump_dir )
	boss.velocity = Vector2( float( _jump_dir ) * Boss.JUMP_SPEED_X , -Boss.JUMP_FORCE )
	timer = 0.0
	pass


func re_enter() -> void:
	pass


func exit() -> void:
	pass


func physics_update( delta : float ) -> void:
	timer += delta
	#水平方向沿用起跳时锁定的方向与力度，空中不做任何落点修正或转向
	boss.velocity.x = float( _jump_dir ) * Boss.JUMP_SPEED_X
	boss.velocity.y = minf( boss.velocity.y + Boss.GRAVITY * delta , Boss.MAX_FALL_SPEED )
	boss.move_and_slide()
	#落地且已离地一小段时间后重新决策（足够近且普攻已过冷却则直接接普攻）
	#这个「够不够近」是落地后的判断，取的是玩家当前位置，不影响空中轨迹
	if timer > Boss.JUMP_GRACE and boss.is_on_floor():
		if absf( boss.dx_to_target() ) <= Boss.ATTACK_RANGE and boss.attack_ready():
			state_machine.change_state( boss.decision_engine.bs_attack )
		else:
			state_machine.change_state( boss.decision_engine.bs_decide )
	pass
