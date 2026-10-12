class_name NPC4 extends NPC1

## NPC4 专属脚本：在 NPC3（商店 NPC，完全继承 NPC1 的交互区 / 对话 / 商店流程）基础上，
## 只调整移动 AI——大幅降低“开始行走”的触发概率，让该 NPC 更多时间停在原地。
##
## 另修正精灵朝向：npc_4 使用的 Archer 素材与 npc_1/2/3 的素材默认朝向相反，
## 基类 _flip_sprite 的镜像逻辑对它正好是反的，这里把符号取反即与移动方向一致。

## 每次静止结束后“开始行走”的概率（0~1）：越小则越少走动，
## 未命中时继续静止，而不是像基类那样必定走动
@export_range( 0.0 , 1.0 , 0.01 ) var walk_probability : float = 0.25


## 覆盖基类：静止计时结束后先掷一次概率，命中才进入行走，否则重新开始一段静止。
## 基类原逻辑是“静止结束必定行走”，这里改成按概率触发以降低行走频率
func _update_idle( delta : float ) -> void:
	_timer += delta
	if _timer >= _state_duration:
		if randf() < walk_probability:
			_start_walking()
		else:
			_start_idle()
	pass


## 覆盖基类：把镜像符号取反，修正 Archer 素材左右相反的问题，
## 使“向右移动 = 精灵朝右、向左移动 = 精灵朝左”
func _flip_sprite( dir : float ) -> void:
	if sprite == null or dir == 0.0:
		return
	var abs_scale : float = absf( sprite.scale.x )
	sprite.scale.x = abs_scale if dir > 0.0 else -abs_scale
	pass
