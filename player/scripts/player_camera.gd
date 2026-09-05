class_name PlayerCamera extends Camera2D

var shake_strengh : float = 0.0
var shake_time_left : float = 0.0
var shake_duration : float = 0.0

@export var max_shake_offset : float = 15.0
@export var default_shake_duration : float = 0.25




func _ready() -> void:
	VisualEffects.camera_shook.connect( _apply_shake )
	SceneManager.new_scene_ready.connect( _on_scene_transition )
	pass


func _process( delta: float ) -> void:
	#时间驱动的确定性抖动：时长固定，振幅随剩余时间线性衰减
	#旧实现用 lerp(strength,0,rate*delta) 指数衰减，帧率相关且 weight>1 时强度翻负导致时长异常
	if shake_time_left > 0.0:
		shake_time_left = maxf( shake_time_left - delta , 0.0 )
		var envelope : float = shake_time_left / shake_duration
		offset = Vector2(
			randf_range( -shake_strengh , shake_strengh ),
			randf_range( -shake_strengh , shake_strengh )
		) * envelope
	else:
		offset = Vector2.ZERO
		shake_strengh = 0.0
		shake_duration = 0.0
	pass


func _apply_shake( strength : float , duration : float ) -> void:
	#取最大值而非覆盖：新触发不会截断/重置正在进行的更强抖动，连续触发时长封顶
	shake_strengh = maxf( shake_strengh , minf( strength , max_shake_offset ) )
	shake_duration = maxf( shake_duration , duration )
	shake_time_left = maxf( shake_time_left , duration )
	pass


func _on_scene_transition( _t , _o ) -> void:
	reset_smoothing.call_deferred()
	pass
