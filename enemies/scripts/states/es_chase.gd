class_name ESChase extends EnemyState

@export var chase_speed : float = 100
## 死区（像素）：与玩家的水平距离小于等于该值时停在原地并保持当前朝向，不再翻面。
## 用于消除贴脸时 sign() 因位置来回越过而反复变号导致的左右抽搐
@export var dead_zone : float = 10.0
## 翻面迟滞（像素）：只有玩家明显移到另一侧、水平距离超过该值才允许翻转精灵朝向；
## 滞回带内仍朝玩家移动但朝向不变，避免临界处来回翻面。需 >= dead_zone
@export var flip_hysteresis : float = 25.0
## 站在悬崖边等待的时间（秒）：等满后跳下平台去追玩家，不再停在边缘作保护
@export var edge_wait_time : float = 0.5
## 跳下悬崖时的向上冲量（正数，实际以负值写进 velocity.y）
@export var edge_jump_force : float = 220.0
## 跳下悬崖的向前速度：起跳瞬间写入 velocity.x，并在落地前保持不变，
## 所以起跳后是一条固定弧线离开平台（空中不再按玩家位置修正落点）
@export var edge_jump_speed : float = 90.0

#已在边缘站立的累计时长（秒）：离开边缘、被死区拦下或跳出后清零
var _edge_timer : float = 0.0
#是否正处在「跳下悬崖」的弧线中：为 true 时空中不再用 chase_speed 覆盖水平速度，
#保持起跳瞬间那条弧线，落地（is_on_floor）后清掉并恢复追击
var _jumping : bool = false

func enter() -> void:
	_edge_timer = 0.0
	_jumping = false
	enemy.play_animation( animation_name if animation_name else "chase" )
	pass


func re_enter() -> void:
	pass


func exit() -> void:
	pass


func physics_update( delta: float ) -> void:
	#已落地：本段跳跃弧线结束，恢复按 chase_speed 追击
	if _jumping and enemy.is_on_floor():
		_jumping = false
	var dx : float = blackboard.target.global_position.x - enemy.global_position.x
	#死区：水平距离极小时视为已到位，停在原地并保持朝向（不翻面）
	if absf( dx ) <= dead_zone:
		enemy.velocity.x = 0.0
		_edge_timer = 0.0
		return
	var dir : float = sign( dx )
	#方向迟滞：只有玩家明显移到另一侧（水平距离超过 flip_hysteresis）才允许翻面；
	#滞回带内继续朝玩家移动，但精灵朝向保持不变，消除临界处来回翻面的抽搐
	if dir != blackboard.dir and absf( dx ) <= flip_hysteresis:
		pass
	else:
		enemy.change_dir( dir )
	#悬崖（EdgeSensor 在前进侧检测到前方无地面）：先站在边缘等 edge_wait_time 秒，
	#等满就朝 EdgeSensor 那一侧跳下平台继续追——不再像以前那样停在边缘原地不动、永不跳下。
	#起跳方向取 blackboard.dir（传感器所在的那一侧），避免方向迟滞期间玩家反向时跳错边。
	#未挂 EdgeSensor 的敌人 blackboard.edge_detected 恒为 false，行为与修改前一致
	if enemy.is_on_floor() and blackboard.edge_detected:
		enemy.velocity.x = 0.0
		_edge_timer += delta
		if _edge_timer >= edge_wait_time:
			_edge_timer = 0.0
			_jumping = true
			enemy.velocity = Vector2( blackboard.dir * edge_jump_speed , -edge_jump_force )
		return
	_edge_timer = 0.0
	#跳跃弧线期间不再覆盖水平速度：保持起跳瞬间的方向与速度，形成固定落点的弧线
	if not _jumping:
		enemy.velocity.x = dir * chase_speed
	pass
