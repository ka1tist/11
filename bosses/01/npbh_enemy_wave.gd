extends Node2D

## 三阶段砸击释放的左右光波：持续朝所在侧平推并逐渐加速，撞到墙壁后淡出销毁。
## 推进方向由生成方（bosses/scripts/boss.gd）设置的 scale.x 决定：负值向左，正值向右。

#初始水平推进速度（像素/秒）
@export var speed : float = 190.0
#推进速度上限（像素/秒）
@export var max_speed : float = 300.0
#每秒加速度（像素/秒²）
@export var acceleration : float = 140.0
#墙壁所在碰撞层（竞技场的地面与左右墙同为第 1 层）
@export var wall_mask : int = 1


func _physics_process( delta : float ) -> void:
	#越推越快，最快到 max_speed
	speed = minf( speed + acceleration * delta , max_speed )
	var dir : float = -1.0 if scale.x < 0.0 else 1.0
	var step : float = speed * delta * dir
	var from : Vector2 = global_position
	var to : Vector2 = from + Vector2( step , 0.0 )
	var space : PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create( from , to , wall_mask )
	var hit : Dictionary = space.intersect_ray( query )
	if hit.is_empty():
		global_position.x += step
	else:
		#前方即墙壁：停下并淡出
		_hit_wall()
	pass


#撞墙：停止推进，淡出后销毁
func _hit_wall() -> void:
	set_physics_process( false )
	var tw := create_tween()
	tw.tween_property( self , "modulate:a" , 0.0 , 0.15 )
	tw.tween_callback( queue_free )
	pass
