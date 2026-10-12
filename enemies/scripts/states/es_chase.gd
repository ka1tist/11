class_name ESChase extends EnemyState

@export var chase_speed : float = 100
## 死区（像素）：与玩家的水平距离小于等于该值时停在原地并保持当前朝向，不再翻面。
## 用于消除贴脸时 sign() 因位置来回越过而反复变号导致的左右抽搐
@export var dead_zone : float = 10.0
## 翻面迟滞（像素）：只有玩家明显移到另一侧、水平距离超过该值才允许翻转精灵朝向；
## 滞回带内仍朝玩家移动但朝向不变，避免临界处来回翻面。需 >= dead_zone
@export var flip_hysteresis : float = 25.0

func enter() -> void:
	enemy.play_animation( animation_name if animation_name else "chase" )
	pass


func re_enter() -> void:
	pass


func exit() -> void:
	pass


func physics_update( _delta: float ) -> void:
	var dx : float = blackboard.target.global_position.x - enemy.global_position.x
	#死区：水平距离极小时视为已到位，停在原地并保持朝向（不翻面）
	if absf( dx ) <= dead_zone:
		enemy.velocity.x = 0.0
		return
	var dir : float = sign( dx )
	#方向迟滞：只有玩家明显移到另一侧（水平距离超过 flip_hysteresis）才允许翻面；
	#滞回带内继续朝玩家移动，但精灵朝向保持不变，消除临界处来回翻面的抽搐
	if dir != blackboard.dir and absf( dx ) <= flip_hysteresis:
		pass
	else:
		enemy.change_dir( dir )
	#平台边缘保护：EdgeSensor 在前进侧检测到前方无地面（悬崖）时停在原地，
	#不再朝玩家追出平台外，避免追击过程中掉下当前所在平台。
	#未挂 EdgeSensor 的敌人 blackboard.edge_detected 恒为 false，行为与修改前一致
	if enemy.is_on_floor() and blackboard.edge_detected:
		enemy.velocity.x = 0.0
		return
	enemy.velocity.x = dir * chase_speed
	pass
