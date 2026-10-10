class_name House
extends Area2D

# 开门音效：交互后 TileMapLayer 可见（回到屋外）时播放
const DOOR_OPEN_AUDIO := preload("uid://deotw4t0rcr5v")
# 关门音效：交互后 TileMapLayer2 / 3 / 4 可见（进入屋内）时播放
const DOOR_CLOSE_AUDIO := preload("uid://c3e1r3g1smm7m")

## 房屋进出交互脚本
## 玩家进入门口的 Area2D 区域后按 action 键（S / X / 手柄 Y），
## 在“屋外”与“屋内”两种状态之间来回切换：
##
## 屋外（默认未交互）：
##   TileMapLayer           可见，物理碰撞关闭（门口区域可自由通行）
##   TileMapLayer2 / 3 / 4  隐藏，物理碰撞关闭
##   LightOccluder2D        可见（外观遮挡阳光投射阴影）
##   SavePoint              隐藏，交互检测关闭（存档点属于室内）
## 屋内（首次交互后）：
##   TileMapLayer           隐藏，物理碰撞关闭
##   TileMapLayer2 / 3 / 4  可见，物理碰撞开启（室内墙体碰撞生效）
##   LightOccluder2D        隐藏（不再遮挡室内灯光）
##   SavePoint              显示，交互检测开启
##   室内 NPC               显示，交互检测开启
##   TileMapLayer5          碰撞常驻：始终开启物理碰撞，不随开关门变化（非视觉图层，不参与淡变）
## 再次交互恢复屋外状态，如此往复。放在房子节点下的 NPC 会自动纳入显隐管理。
##
## 离开自动回屋外（HouseArea 房屋整体区域）：
##   屋内状态下玩家走出房屋整体区域后，不会立刻切换，而是进入 leave_delay_seconds
##   延迟判定；延迟内走回区域则取消切换，避免在区域边界来回蹭导致画面闪烁。
##   延迟结束仍在区域外才自动切回屋外，切换时复用门音效并播放图层交叉淡变过渡。
##
## 场景过渡（消除图层切换闪烁，无屏幕遮罩）：
##   进屋 / 出屋时外观与内景两组图层同时保持可见，对各自 modulate.a 做时间相同的
##   交叉淡入淡出（cross-fade）：旧场景渐隐的同时新场景渐现，画面始终有内容、不黑场、
##   不跳变；室内 NPC 跟随一起淡变。物理碰撞 / 光照遮挡体 / NPC 交互区这类“非视觉”
##   状态在淡变中点统一切换——中点两侧都处于半透明混合状态，阴影与碰撞的瞬时变化被
##   交叉溶解掩盖。全程时间驱动插值，任何帧率下节奏一致。

## 玩家离开房屋区域后自动切回屋外的延迟（秒）：期间返回区域即取消，建议 0.5~1.0
@export_range( 0.05 , 3.0 , 0.05 , "suffix:s" ) var leave_delay_seconds : float = 0.7
## 是否启用“离开房屋区域自动切回屋外”；false 时只能通过门口手动交互切回
@export var auto_switch_on_leave : bool = true
## 区域占用轮询间隔（秒）：除进出信号外，每隔该间隔复核一次玩家是否仍在区域内，
## 用于补偿极端情况下的信号丢失。值越小灵敏度越高、CPU 开销越大；0 = 仅依赖进出信号
@export_range( 0.0 , 1.0 , 0.01 , "suffix:s" ) var detection_poll_interval : float = 0.1
## 进/出屋交叉淡变时长（秒）：0 = 瞬时切换（无过渡）。时间驱动，与帧率无关
@export_range( 0.0 , 1.5 , 0.02 , "suffix:s" ) var transition_duration : float = 0.24

# 外观图层（屋顶 / 外墙）
@onready var _exterior_layer: TileMapLayer = $Sprite2D/TileMapLayer
# 室内图层 1（地板 / 内墙等）
@onready var _interior_layer_2: TileMapLayer = $Sprite2D/TileMapLayer2
# 室内图层 2（家具 / 装饰等）
@onready var _interior_layer_3: TileMapLayer = $Sprite2D/TileMapLayer3
# 室内图层 3（装饰等）
@onready var _interior_layer_4: TileMapLayer = $Sprite2D/TileMapLayer4
# 碰撞常驻图层（房子02 的 TileMapLayer5，楼梯 / 台阶等）：物理碰撞始终开启，
# 不参与开关门的碰撞切换。房子01 等没有该节点的场景取到 null，自动跳过
@onready var _constant_collision_layer: TileMapLayer = get_node_or_null( "Sprite2D/TileMapLayer5" ) as TileMapLayer
# 房屋整体区域：监测玩家是否还在房屋范围内，离开后延迟自动切回屋外
@onready var _house_area: Area2D = $HouseArea

## 室内 NPC 列表：放在房子节点下的所有 NPC，进屋时显示并可交互，出屋时隐藏并禁用交互
var _interior_npcs: Array[NPC] = []
## 房屋外观的光照遮挡体列表：可见性跟随外观图层（屋外投射阴影，屋内不遮挡）
var _exterior_occluders: Array[LightOccluder2D] = []
## 室内存档点列表：可见性跟随内景图层（屋内显示，屋外隐藏）
var _interior_save_points: Array[SavePoint] = []

## false = 屋外（默认未交互状态）；true = 屋内
var _is_inside: bool = false
## 玩家是否正处于门口交互区域内，用于防止交互信号重复连接 / 断开
var _player_in_range: bool = false

## 玩家当前是否处于房屋整体区域（HouseArea）内
var _player_in_house: bool = false
## 离开房屋区域后的自动切回计时是否进行中
var _leave_pending: bool = false
## 计时令牌：每次进入区域 / 重新启动计时时自增，旧计时醒来发现令牌过期即作废，避免竞态
var _leave_token: int = 0
## 轮询累计时间（秒）
var _poll_accum: float = 0.0
## 当前交叉淡变的逻辑时序 tween（中点 / 结束回调），完成即置空
var _transition_tween: Tween = null
## 当前交叉淡变的透明度动画 tween（与逻辑 tween 同时被杀掉）
var _transition_anim: Tween = null


func _ready() -> void:
	# 收集房子下的所有 NPC（如 InteriorNPC）、外观光照遮挡体和存档点，随房屋状态一起显隐
	for node in find_children("*"):
		if node is NPC:
			_interior_npcs.append(node)
		elif node is LightOccluder2D:
			_exterior_occluders.append(node)
		elif node is SavePoint:
			_interior_save_points.append(node)
	# 进入场景时强制应用一次默认状态，保证运行时状态确定，不依赖编辑器里的图层配置
	_apply_state()
	# 门口交互区检测：沿用项目里开关 / 宝箱的交互范式
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	# 房屋整体区域检测：玩家离开后延迟自动切回屋外
	_house_area.body_entered.connect(_on_house_body_entered)
	_house_area.body_exited.connect(_on_house_body_exited)
	# 兼容玩家出生点就在区域内的情况（例如场景切换后落在门口 / 屋内）
	await get_tree().physics_frame
	for body in get_overlapping_bodies():
		if body is Player:
			_set_player_in_range(true)
			break
	_set_player_in_house(_is_player_in_area(_house_area))


# ---------- 状态切换 ----------

## 切换房屋状态（屋外 <-> 屋内），并按切换后的图层可见性播放对应门音效
func toggle_state() -> void:
	_request_state(not _is_inside)


## 状态切换的统一请求入口：手动交互与“离开自动回屋外”都走这里。
## target_inside=false 切回屋外、true 进入屋内；状态相同时不做任何事。
func _request_state(target_inside: bool) -> void:
	if _is_inside == target_inside:
		return
	_is_inside = target_inside
	if transition_duration > 0.0:
		_play_transition()
	else:
		_apply_state()
	#进屋（内景图层可见）播放关门声，出屋（外观图层可见）播放开门声
	var sound := DOOR_CLOSE_AUDIO if _is_inside else DOOR_OPEN_AUDIO
	Audio.play_spatial_sound(sound, global_position)


## 图层交叉淡变（无屏幕遮罩）：外观组与内景组在整段时间内同时可见，
## 旧组 modulate.a→0、新组 →1，画面始终有内容；碰撞 / 遮挡体 / NPC 交互在中点切换，
## 结束后按最终状态整理可见性并复位透明度。中途再次触发时杀掉旧 tween、从当前
## 透明度反向续接。transition_duration=0 时不走这里（瞬时切换）
func _play_transition() -> void:
	_kill_transition()
	# 淡变期间两组图层 / NPC 都必须可见；隐藏组先把 alpha 归零再显示，杜绝露出一帧
	_show_for_fade(_exterior_layer)
	_show_for_fade(_interior_layer_2)
	_show_for_fade(_interior_layer_3)
	_show_for_fade(_interior_layer_4)
	# 淡变期间冻结 NPC 物理：内景碰撞在中点才切换，前半程没有地面，不冻结会原地坠落
	for npc in _interior_npcs:
		_show_for_fade(npc)
		npc.set_physics_process(false)
	# 存档点随内景图层一起淡变（静态节点，无物理需要冻结）
	for save_point in _interior_save_points:
		_show_for_fade(save_point)
	var duration := maxf(transition_duration, 0.001)
	var exterior_target := 0.0 if _is_inside else 1.0
	var interior_target := 1.0 if _is_inside else 0.0
	# 并行 tween 同时驱动全部透明度；SINE 双向缓动让交叉混合中段更柔和
	var anim := create_tween().set_parallel(true)
	_tween_alpha(anim, _exterior_layer, exterior_target, duration)
	_tween_alpha(anim, _interior_layer_2, interior_target, duration)
	_tween_alpha(anim, _interior_layer_3, interior_target, duration)
	_tween_alpha(anim, _interior_layer_4, interior_target, duration)
	for npc in _interior_npcs:
		_tween_alpha(anim, npc, interior_target, duration)
	for save_point in _interior_save_points:
		_tween_alpha(anim, save_point, interior_target, duration)
	_transition_anim = anim
	# 顺序 tween 负责“中点切逻辑状态 + 结束整理可见性”，时长与动画严格对齐
	_transition_tween = create_tween()
	_transition_tween.tween_interval(duration * 0.5)
	_transition_tween.tween_callback(_apply_midpoint_state)
	_transition_tween.tween_interval(duration * 0.5)
	_transition_tween.tween_callback(_finish_transition)


## 让节点参与交叉淡变：不可见的节点先置全透明再显示，已可见的节点保留当前透明度，
## 使“中途打断反向续接”能从当前混合程度平滑继续
func _show_for_fade(node: CanvasItem) -> void:
	if not node.visible:
		node.modulate.a = 0.0
		node.visible = true


func _tween_alpha(tween: Tween, node: CanvasItem, target_alpha: float, duration: float) -> void:
	tween.tween_property(node, "modulate:a", target_alpha, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## 淡变中点：切换所有“非视觉”状态。此时两侧图层都约半透明，碰撞与阴影的瞬时变化
## 被交叉混合掩盖（外观图层碰撞恒定关闭，无需参与）
func _apply_midpoint_state() -> void:
	# 室内图层碰撞仅在屋内开启：屋外开启会让看不见的墙体阻挡玩家
	_interior_layer_2.collision_enabled = _is_inside
	_interior_layer_3.collision_enabled = _is_inside
	_interior_layer_4.collision_enabled = _is_inside
	# 碰撞常驻图层：无论开门 / 关门都保持碰撞开启，不随房屋状态变化
	if _constant_collision_layer != null:
		_constant_collision_layer.collision_enabled = true
	# 外观光照遮挡体：屋外遮挡阳光投影，屋内隐藏避免挡住室内灯光
	for occluder in _exterior_occluders:
		occluder.visible = not _is_inside
	# NPC 交互检测跟随中点，避免隔着半透明墙体提前 / 滞后触发对话
	for npc in _interior_npcs:
		if npc is NPC1:
			(npc as NPC1).set_interaction_enabled(_is_inside)
	# 存档点交互检测同样跟随中点：屋外不再对隐形的存档点提示“可交互”或触发存档
	for save_point in _interior_save_points:
		save_point.set_interaction_enabled(_is_inside)


## 过渡正常结束：按最终状态整理可见性（先隐藏再把 alpha 复位为 1，复位发生在
## 不可见节点上无视觉影响），恢复 NPC 物理
func _finish_transition() -> void:
	_transition_tween = null
	_transition_anim = null
	_exterior_layer.visible = not _is_inside
	_interior_layer_2.visible = _is_inside
	_interior_layer_3.visible = _is_inside
	_interior_layer_4.visible = _is_inside
	_exterior_layer.modulate.a = 1.0
	_interior_layer_2.modulate.a = 1.0
	_interior_layer_3.modulate.a = 1.0
	_interior_layer_4.modulate.a = 1.0
	for npc in _interior_npcs:
		npc.visible = _is_inside
		npc.modulate.a = 1.0
		npc.set_physics_process(true)
	for save_point in _interior_save_points:
		save_point.visible = _is_inside
		save_point.modulate.a = 1.0
	# 终态再确认一次碰撞 / 遮挡体 / 交互，覆盖“恰好在中点前被打断”等边界时序
	_apply_midpoint_state()


func _kill_transition() -> void:
	for tween in [_transition_tween, _transition_anim]:
		if tween != null and tween.is_valid():
			tween.kill()
	_transition_tween = null
	_transition_anim = null


## 瞬时状态应用（transition_duration=0）：根据 _is_inside 一次性设置
## 三个图层的可见性 / 透明度 / 物理碰撞，以及遮挡体、存档点与 NPC
func _apply_state() -> void:
	# 外观图层：屋外可见、屋内隐藏；任何状态下都关闭其 TileSet 物理层碰撞，
	# 这样玩家在屋外能走进门口区域，进屋后也不会被隐藏的外墙卡住
	_exterior_layer.visible = not _is_inside
	_exterior_layer.modulate.a = 1.0
	_exterior_layer.collision_enabled = false

	# 室内三个图层：仅在屋内可见，可见时才开启 TileSet 物理层碰撞；
	# 隐藏时必须一并关闭碰撞，否则看不见的墙体会在屋外阻挡玩家
	_interior_layer_2.visible = _is_inside
	_interior_layer_3.visible = _is_inside
	_interior_layer_4.visible = _is_inside
	_interior_layer_2.modulate.a = 1.0
	_interior_layer_3.modulate.a = 1.0
	_interior_layer_4.modulate.a = 1.0
	_interior_layer_2.collision_enabled = _is_inside
	_interior_layer_3.collision_enabled = _is_inside
	_interior_layer_4.collision_enabled = _is_inside
	# 碰撞常驻图层：无论开门 / 关门都保持碰撞开启，不随房屋状态变化
	if _constant_collision_layer != null:
		_constant_collision_layer.collision_enabled = true

	# 外观光照遮挡体与外观图层同步：屋外遮挡阳光投下房屋阴影，进屋后隐藏，
	# 避免室内灯光被看不见的外墙 / 屋顶挡住
	for occluder in _exterior_occluders:
		occluder.visible = not _is_inside

	# 室内 NPC 随房屋状态显隐；隐藏时同时关闭其交互检测区，
	# 否则在屋外也能隔着墙触发对话提示 / 对话
	for npc in _interior_npcs:
		npc.visible = _is_inside
		npc.modulate.a = 1.0
		npc.set_physics_process(true)
		if npc is NPC1:
			(npc as NPC1).set_interaction_enabled(_is_inside)

	# 室内存档点随房屋状态显隐；隐藏时一并关闭交互检测，
	# 否则屋外能走进房屋轮廓内碰到隐形的存档点并触发存档
	for save_point in _interior_save_points:
		save_point.visible = _is_inside
		save_point.modulate.a = 1.0
		save_point.set_interaction_enabled(_is_inside)


# ---------- Area2D 区域检测 ----------

func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		_set_player_in_range(true)


func _on_body_exited(body: Node2D) -> void:
	if body is Player:
		_set_player_in_range(false)


## 玩家进入 / 离开交互区域：刷新按键提示，并（取消）订阅全局交互信号
func _set_player_in_range(in_range: bool) -> void:
	if _player_in_range == in_range:
		return
	_player_in_range = in_range
	if in_range:
		# 显示“可交互”提示，玩家按 action 键时由 Player 广播 player_interacted
		Messages.input_hint_changed.emit("interact")
		Messages.player_interacted.connect(_on_player_interact)
	else:
		Messages.input_hint_changed.emit("")
		if Messages.player_interacted.is_connected(_on_player_interact):
			Messages.player_interacted.disconnect(_on_player_interact)


## 玩家在区域内按下 action 键时触发：切换房屋状态
func _on_player_interact(_player: Player) -> void:
	if _player_in_range:
		toggle_state()


# ---------- 房屋整体区域检测（离开自动回屋外） ----------

func _physics_process(delta: float) -> void:
	# 轮询补偿：detection_poll_interval=0 时完全信号驱动，不做任何每帧检测
	if detection_poll_interval <= 0.0:
		return
	_poll_accum += delta
	if _poll_accum < detection_poll_interval:
		return
	_poll_accum = 0.0
	# 定期复核玩家是否仍在房屋区域内，与进出信号汇入同一个状态入口（内部自带去重）
	var present := _is_player_in_area(_house_area)
	if present != _player_in_house:
		_set_player_in_house(present)


func _on_house_body_entered(body: Node2D) -> void:
	if body is Player:
		_set_player_in_house(true)


func _on_house_body_exited(body: Node2D) -> void:
	if body is Player:
		_set_player_in_house(false)


## 指定区域内当前是否重叠着玩家
func _is_player_in_area(area: Area2D) -> bool:
	for body in area.get_overlapping_bodies():
		if body is Player:
			return true
	return false


## 更新玩家在房屋区域内的占用状态：
## 进入区域 → 取消待执行的自动切回；离开区域且当前处于屋内 → 启动延迟判定
func _set_player_in_house(in_house: bool) -> void:
	if _player_in_house == in_house:
		return
	_player_in_house = in_house
	if in_house:
		# 令牌自增使任何等待中的离开计时立即作废
		_leave_token += 1
		_leave_pending = false
	elif auto_switch_on_leave and _is_inside:
		_start_leave_timer()


## 离开延迟判定：计时期间玩家返回（或状态被手动切换、节点被释放）则放弃切回，
## 持续在区域外待满 leave_delay_seconds 才自动切回屋外
func _start_leave_timer() -> void:
	_leave_token += 1
	var token := _leave_token
	_leave_pending = true
	# 用物理帧计时：固定 60Hz 步进，不受帧率波动 / 卡顿影响，延迟判定稳定
	await get_tree().create_timer(leave_delay_seconds, true, true).timeout
	if token != _leave_token or not is_instance_valid(self):
		return
	_leave_pending = false
	# 计时期间可能已通过门口手动交互切回屋外；双重确认后才执行自动切换
	if _is_inside and not _player_in_house:
		_request_state(false)


func _exit_tree() -> void:
	# 作废所有等待中的离开计时，防止场景卸载后回调访问已释放节点
	_leave_token += 1
	# 杀掉未播完的过渡，避免 tween 回调在节点释放途中触发
	_kill_transition()
	# 场景卸载时若信号仍连着，主动断开避免报错
	if Messages.player_interacted.is_connected(_on_player_interact):
		Messages.player_interacted.disconnect(_on_player_interact)
