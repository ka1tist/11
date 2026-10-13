class_name HitParticles extends GPUParticles2D

#素材默认初速：进树时记录（材质是每个实例独立的副本，可安全改写）
var _base_velocity_min : float = 0.0
var _base_velocity_max : float = 0.0


func _ready() -> void:
	_base_velocity_min = process_material.initial_velocity_min
	_base_velocity_max = process_material.initial_velocity_max
	pass


func start( dir : Vector2 , settings : HitParticleSettings ) -> void:
	var speed_mult : float = 1.0
	if settings:
		amount = settings.count
		modulate = settings.color
		texture = settings.texture
		speed_mult = settings.speed_mult
	process_material.initial_velocity_min = _base_velocity_min * speed_mult
	process_material.initial_velocity_max = _base_velocity_max * speed_mult
	process_material.direction = Vector3( dir.x , dir.y , 0 )
	emitting = true
	await finished
	queue_free()
	pass
