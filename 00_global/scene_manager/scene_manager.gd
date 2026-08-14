extends CanvasLayer

signal load_scene_started
signal new_scene_ready( target_name : String , offset : Vector2 )
signal load_scene_finished
signal scene_entered( uid : String )

@onready var fade: Control = $Fade

var current_scene_uid : String


func _ready() -> void:
	fade.visible = false
	await get_tree().process_frame
	load_scene_finished.emit()
	var current_scene : String = get_tree().current_scene.scene_file_path
	current_scene_uid = ResourceUID.path_to_uid( current_scene )
	pass




func transition_scene( new_scene : String , target_area : String , player_offset:Vector2 , dir : String) -> void:
		#淡出新场景
		get_tree().paused = true
		
		var fade_pos : Vector2 = get_fade_pos( dir )
		
		fade.visible = true
		
		load_scene_started.emit()

		# 在淡出动画开始时同步启动后台加载，让加载耗时被动画掩盖
		ResourceLoader.load_threaded_request( new_scene )

		await fade_screen( fade_pos , Vector2.ZERO )

		# 等待后台加载完成，避免主线程阻塞造成卡顿
		var progress : Array = []
		while ResourceLoader.load_threaded_get_status( new_scene , progress ) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			await get_tree().process_frame

		# 加载完成后再切换场景（此时资源已在内存中，切换瞬时完成）
		var packed : PackedScene = ResourceLoader.load_threaded_get( new_scene )
		get_tree().change_scene_to_packed( packed )
		
		current_scene_uid = ResourceUID.path_to_uid( new_scene )
		scene_entered.emit( current_scene_uid )

		await get_tree().scene_changed
		
		new_scene_ready.emit( target_area , player_offset )
		
		#淡入新场景
		await get_tree().process_frame
		await fade_screen( Vector2.ZERO , -fade_pos )
		
		fade.visible = false
		get_tree().paused = false
		
		load_scene_finished.emit()
		
		pass



func fade_screen( from : Vector2, to : Vector2 ) -> Signal:
	fade.position = from
	var tween : Tween = create_tween()
	tween.tween_property( fade,"position",to,0.1 )
	return tween.finished


func get_fade_pos( dir :String) -> Vector2:
	var pos : Vector2 = Vector2( 640*2 , 360*2 )
	
	match dir:
		"left":
			pos *= Vector2( -1,0 )
		"right":
			pos *= Vector2( 1,0 )
		"up":
			pos *= Vector2( 0,-1 )
		"down":
			pos *= Vector2( 0,1 )
	
	return pos
