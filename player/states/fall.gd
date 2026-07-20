class_name PlayerStateFall extends PlayerState

#状态初始化时做什么
func init() -> void:
	pass
	
#当我们进入这个状态时会发生什么
func enter() -> void:
	#动画
	pass
	
#当我们退出这个状态会发生什么
func exit() -> void:
	pass

#按下输入会发生什么
func handle_input( _event : InputEvent ) -> PlayerState:
	#处理输入
	return next_state
	
	
#在这个状态下，每个过程tick会发生什么
func process(_delta: float) -> PlayerState:

	return next_state


#在这个状态下，每个物理过程tick会发生什么
func physics_process(_delta: float) -> PlayerState:

	return next_state
