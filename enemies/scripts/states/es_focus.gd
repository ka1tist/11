class_name ESFocus extends EnemyState


#发现玩家时的聚焦/警觉状态：原地播放一遍 focus 动画（不移动），
#动画播放期间锁住决策，播完后 can_decide 恢复，由决策引擎转入追击/攻击。

var duration : float = 0
var timer : float = 0


func start() -> void:
	var anim : String = animation_name if animation_name else "focus"
	if enemy.animation.current_animation == anim:
		enemy.animation.seek( 0 )
	else:
		enemy.play_animation( anim )
	duration = enemy.animation.current_animation_length
	timer = 0
	blackboard.can_decide = false
	pass


func enter() -> void:
	start()
	pass


func re_enter() -> void:
	start()
	pass


func exit() -> void:
	blackboard.can_decide = true
	pass


func physics_update( delta: float ) -> void:
	timer += delta
	enemy.velocity.x = 0
	if timer >= duration :
		blackboard.can_decide = true
	pass
