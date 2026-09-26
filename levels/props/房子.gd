class_name House
extends Area2D

# 开门音效：交互后 TileMapLayer 可见（回到屋外）时播放
const DOOR_OPEN_AUDIO := preload("uid://mtst6r5b6tqh")
# 关门音效：交互后 TileMapLayer2 / 3 可见（进入屋内）时播放
const DOOR_CLOSE_AUDIO := preload("uid://deotw4t0rcr5v")

## 房屋进出交互脚本
## 玩家进入门口的 Area2D 区域后按 action 键（S / X / 手柄 Y），
## 在“屋外”与“屋内”两种状态之间来回切换：
##
## 屋外（默认未交互）：
##   TileMapLayer           可见，物理碰撞关闭（门口区域可自由通行）
##   TileMapLayer2 / 3      隐藏，物理碰撞关闭
##   LightOccluder2D        可见（外观遮挡阳光投射阴影）
## 屋内（首次交互后）：
##   TileMapLayer           隐藏，物理碰撞关闭
##   TileMapLayer2 / 3      可见，物理碰撞开启（室内墙体碰撞生效）
##   LightOccluder2D        隐藏（不再遮挡室内灯光）
##   室内 NPC               显示，交互检测开启
## 再次交互恢复屋外状态，如此往复。放在房子节点下的 NPC 会自动纳入显隐管理。

# 外观图层（屋顶 / 外墙）
@onready var _exterior_layer: TileMapLayer = $Sprite2D/TileMapLayer
# 室内图层 1（地板 / 内墙等）
@onready var _interior_layer_2: TileMapLayer = $Sprite2D/TileMapLayer2
# 室内图层 2（家具 / 装饰等）
@onready var _interior_layer_3: TileMapLayer = $Sprite2D/TileMapLayer3

## 室内 NPC 列表：放在房子节点下的所有 NPC，进屋时显示并可交互，出屋时隐藏并禁用交互
var _interior_npcs: Array[NPC] = []
## 房屋外观的光照遮挡体列表：可见性跟随外观图层（屋外投射阴影，屋内不遮挡）
var _exterior_occluders: Array[LightOccluder2D] = []

## false = 屋外（默认未交互状态）；true = 屋内
var _is_inside: bool = false
## 玩家是否正处于交互区域内，用于防止交互信号重复连接 / 断开
var _player_in_range: bool = false


func _ready() -> void:
	# 收集房子下的所有 NPC（如 InteriorNPC）和外观光照遮挡体，随房屋状态一起显隐
	for node in find_children("*"):
		if node is NPC:
			_interior_npcs.append(node)
		elif node is LightOccluder2D:
			_exterior_occluders.append(node)
	# 进入场景时强制应用一次默认状态，保证运行时状态确定，不依赖编辑器里的图层配置
	_apply_state()
	# 区域检测：沿用项目里开关 / 宝箱的交互范式
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	# 兼容玩家出生点就在交互区域内的情况（例如场景切换后落在门口）
	await get_tree().physics_frame
	for body in get_overlapping_bodies():
		if body is Player:
			_set_player_in_range(true)
			break


# ---------- 状态切换 ----------

## 切换房屋状态（屋外 <-> 屋内），并按切换后的图层可见性播放对应门音效
func toggle_state() -> void:
	_is_inside = not _is_inside
	_apply_state()
	#进屋（内景图层可见）播放关门声，出屋（外观图层可见）播放开门声
	var sound := DOOR_CLOSE_AUDIO if _is_inside else DOOR_OPEN_AUDIO
	Audio.play_spatial_sound(sound, global_position)


## 状态应用的唯一入口：根据 _is_inside 统一控制三个图层的可见性与物理碰撞
func _apply_state() -> void:
	# 外观图层：屋外可见、屋内隐藏；任何状态下都关闭其 TileSet 物理层碰撞，
	# 这样玩家在屋外能走进门口区域，进屋后也不会被隐藏的外墙卡住
	_exterior_layer.visible = not _is_inside
	_exterior_layer.collision_enabled = false

	# 外观光照遮挡体与外观图层同步：屋外遮挡阳光投下房屋阴影，进屋后隐藏，
	# 避免室内灯光被看不见的外墙 / 屋顶挡住
	for occluder in _exterior_occluders:
		occluder.visible = not _is_inside

	# 室内两个图层：仅在屋内可见，可见时才开启 TileSet 物理层碰撞；
	# 隐藏时必须一并关闭碰撞，否则看不见的墙体会在屋外阻挡玩家
	_interior_layer_2.visible = _is_inside
	_interior_layer_3.visible = _is_inside
	_interior_layer_2.collision_enabled = _is_inside
	_interior_layer_3.collision_enabled = _is_inside

	# 室内 NPC 随房屋状态显隐；隐藏时同时关闭其交互检测区，
	# 否则在屋外也能隔着墙触发对话提示 / 对话
	for npc in _interior_npcs:
		npc.visible = _is_inside
		if npc is NPC1:
			(npc as NPC1).set_interaction_enabled(_is_inside)


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


func _exit_tree() -> void:
	# 场景卸载时若信号仍连着，主动断开避免报错
	if Messages.player_interacted.is_connected(_on_player_interact):
		Messages.player_interacted.disconnect(_on_player_interact)
