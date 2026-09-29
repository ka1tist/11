extends Node
## 房子（House）区域检测与离开自动切回屋外 —— 单元测试
##
## 运行方式（物理帧按真实时间 60Hz 步进，延迟判定用物理计时，帧数计数确定）：
##   Godot_v4.7.2-stable_win64_console.exe --headless \
##       --path <项目根目录> res://tests/test_house_area.tscn
## 全部断言通过时进程退出码为 0，存在失败时为 1。
##
## 覆盖内容：
##   1. 初始状态（图层 / 碰撞 / HouseArea 层级配置）
##   2. 进入房屋区域的检测准确性（信号路径）
##   3. 门口交互区之外按交互键不会误切换
##   4. 现有门口交互、NPC 显隐与交互启用完全兼容
##   5. 离开后延迟期内不切换（防抖）
##   6. 延迟内返回区域取消切换，且取消后不会补切
##   7. 持续离开延迟结束自动切回屋外（图层 / 碰撞 / NPC 全部复位）
##   8. 屋外状态下进出区域不会误触发
##   9. 快速进出（边界抖动）只在最后一次离开停留足够久后切换
##   10. auto_switch_on_leave=false 时离开不自动切换
##   11. 自定义 leave_delay_seconds 生效
##   12. 轮询补偿：进出信号被阻断时仍能纠正占用状态并完成自动切回
##   13. 多轮“进屋 -> 自动出屋 -> 再进屋 -> 手动出屋”端到端循环
##   14. 图层交叉淡变（无屏幕遮罩）：内外景半程同时可见且半透明、NPC 跟随淡变与
##       物理冻结、碰撞/遮挡体/交互中点切换、长时长中点时序、中途打断续接、
##       过渡帧耗时采样（30fps 门槛）

const HOUSE_SCENE := preload("res://levels/props/房子.tscn")
const PLAYER_SCENE := preload("res://player/player.tscn")

# 测试坐标（房子实例放在世界原点；房屋五边形区域约 x∈[-159,159], y∈[-376,-1]）
const POS_INSIDE: Vector2 = Vector2(0, -180)
const POS_DOOR: Vector2 = Vector2(-127, -46)
# 远处屋外：用于“持续离开”等不卡边界时间的用例
const POS_OUTSIDE: Vector2 = Vector2(0, 250)
# 刚出房屋边界的近点：胶囊体（中心偏移 -26、半高 26.5）完全离开五边形底边（y≈-2），
# 到屋内点的移动仅 ~0.22s。时间敏感用例必须用近点，否则路途时间会吃掉防抖延迟预算
const POS_OUTSIDE_NEAR: Vector2 = Vector2(0, 80)

# 默认防抖延迟 0.7s、过渡 0.24s（与房子.gd 默认导出值保持一致）
const DEFAULT_DELAY: float = 0.7
const DEFAULT_TRANSITION: float = 0.24
# 等待一次完整过渡的余量时间：默认过渡总长 0.24s（淡出+定格+淡入），留足调度余量
const WAIT_TRANSITION: float = 0.4
# 测试中玩家的移动速度（像素/秒）：由测试控制器通过 move_and_slide 驱动，
# 必须远小于“最小检测区尺寸×60”，保证一帧不会跨过整个区域导致信号漏发
const MOVE_SPEED: float = 1200.0
# 到达目标点的判定距离（像素）
const ARRIVE_EPS: float = 0.5

var _pass: int = 0
var _fail: int = 0
var _world: Node2D
var _house: House
var _player: Player
var _npc: NPC1
## 玩家本帧的移动目标点：测试控制器在玩家自身物理回调之后用 move_and_slide 驱动到达。
## 不能直接赋值 global_position —— CharacterBody2D 的直接传送不会可靠刷新物理宽相，
## Area2D 的进出信号会漏发；move_and_slide 的位移才会稳定经过物理服务器
var _move_target: Vector2 = POS_OUTSIDE


func _ready() -> void:
	# 当前场景树仍在初始化子节点，延迟一帧再搭建测试世界，避免 add_child 失败
	process_priority = 100
	await get_tree().process_frame
	await _run()
	print("==================================================")
	print("房屋区域测试结果：%d 通过 / %d 失败" % [_pass, _fail])
	# 退出前释放测试节点（玩家 _ready 会把自己 reparent 到根节点，需单独释放）
	_player.queue_free()
	_player = null
	_world.queue_free()
	# 等两帧让 queue_free 的延迟释放完成刷盘，避免退出时偶发 ObjectDB 泄漏告警
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(1 if _fail > 0 else 0)


func _physics_process(delta: float) -> void:
	# process_priority=100 保证在玩家自身 _physics_process（重力/move_and_slide/状态机）之后执行
	if _player == null or not is_instance_valid(_player):
		return
	var to_target := _move_target - _player.global_position
	if to_target.length() > ARRIVE_EPS:
		# 末帧精确到达目标点，避免越过；其余帧匀速移动
		var step_len := MOVE_SPEED * delta
		_player.velocity = to_target.limit_length(step_len) / delta
		_player.move_and_slide()
		# 立即清零，避免下一帧玩家自身物理回调先于本控制器用残余速度多走一步（位置抖动）
		_player.velocity = Vector2.ZERO
	else:
		_player.velocity = Vector2.ZERO


func _run() -> void:
	# 真实房子场景 + 真实玩家场景，使用引擎物理空间验证 Area2D 进出
	_world = Node2D.new()
	get_tree().root.add_child(_world)
	_house = HOUSE_SCENE.instantiate()
	_world.add_child(_house)
	_player = PLAYER_SCENE.instantiate()
	_player.global_position = POS_OUTSIDE
	_world.add_child(_player)
	_npc = _house.get_node("InteriorNPC")
	# 等待房子 / NPC 的 _ready（含一物理帧后的初始重叠扫描）完成
	await _wait(0.2)
	# 关闭重力：测试世界没有地面；清零碰撞掩码：move_and_slide 不与地块/家具碰撞，
	# 玩家自身仍在第 16 物理层，Area2D 对玩家的检测完全不受影响
	_player.gravity = 0.0
	_player.collision_mask = 0
	_player.velocity = Vector2.ZERO

	await _test_initial_state()
	await _test_enter_detection()
	await _test_interact_only_at_door()
	await _test_manual_enter_compat()
	await _test_debounce_waits_delay()
	await _test_return_cancels_switch()
	await _test_auto_leave_after_delay()
	await _test_no_trigger_when_exterior()
	await _test_rapid_in_out()
	await _test_disable_auto_switch()
	await _test_custom_delay()
	await _test_polling_fallback()
	await _test_repeated_cycles()
	await _test_smooth_transition()


# ---------- 测试用例 ----------

func _test_initial_state() -> void:
	_section("1. 初始状态")
	_check(_house._is_inside == false, "默认应为屋外状态")
	_check(_house._house_area.collision_mask == 16, "HouseArea 应只监测玩家层(mask=16)")
	_check(_house._house_area.collision_layer == 0, "HouseArea 自身不占物理层(layer=0)，不影响其他检测")
	_check(_house._exterior_layer.visible == true, "初始外观图层可见")
	_check(_house._interior_layer_2.visible == false, "初始室内图层2隐藏")
	_check(_house._interior_layer_3.visible == false, "初始室内图层3隐藏")
	_check(_house._interior_layer_2.collision_enabled == false, "初始室内图层2碰撞关闭")
	_check(_house._interior_layer_3.collision_enabled == false, "初始室内图层3碰撞关闭")
	_check(_house._player_in_house == false, "玩家在区域外时 _player_in_house=false")
	_check(_npc.visible == false, "初始室内 NPC 隐藏")
	_check(_house.leave_delay_seconds == DEFAULT_DELAY, "默认离开延迟为 0.7s")


func _test_enter_detection() -> void:
	_section("2. 进入房屋区域检测")
	await _move_to(POS_INSIDE)
	_check(_house._player_in_house == true, "玩家进入区域后 _player_in_house=true")
	_check(_house._is_player_in_area(_house._house_area) == true, "区域重叠查询应能查到玩家")


func _test_interact_only_at_door() -> void:
	_section("3. 非门口交互区按交互键不切换")
	_check(_house._player_in_range == false, "房屋深处不在门口交互区内")
	Messages.player_interacted.emit(_player)
	await _wait(WAIT_TRANSITION)
	_check(_house._is_inside == false, "不在门口按交互键不应进屋")


func _test_manual_enter_compat() -> void:
	_section("4. 门口手动进屋（现有交互兼容 + NPC 联动）")
	await _move_to(POS_DOOR)
	_check(_house._player_in_range == true, "到达门口后进入交互区")
	Messages.player_interacted.emit(_player)
	await _wait(WAIT_TRANSITION)
	_check(_house._is_inside == true, "门口按交互键进入屋内")
	_check(_house._exterior_layer.visible == false, "进屋后外观图层隐藏")
	_check(_house._interior_layer_2.visible == true, "进屋后室内图层2可见")
	_check(_house._interior_layer_3.visible == true, "进屋后室内图层3可见")
	_check(_house._interior_layer_2.collision_enabled == true, "进屋后室内图层2碰撞开启")
	_check(_npc.visible == true, "进屋后室内 NPC 显示")
	_check(_npc._interaction_area.monitoring == true, "进屋后 NPC 交互检测启用")


func _test_debounce_waits_delay() -> void:
	_section("5. 离开后的防抖延迟")
	await _move_to(POS_OUTSIDE_NEAR)
	# 计时从跨越边界（到达前不久）开始，留足余量
	await _wait(DEFAULT_DELAY - 0.4)
	_check(_house._is_inside == true, "离开未达延迟（%.1fs）仍为屋内" % (DEFAULT_DELAY - 0.4))
	_check(_house._leave_pending == true, "延迟判定进行中 _leave_pending=true")


func _test_return_cancels_switch() -> void:
	_section("6. 延迟内返回区域取消切换")
	# 与用例 5 共享同一次离开：此前已过 ~0.3s，再等 0.1s 后返回，
	# 屋外总时长（含返程跨边界时间）仍明显小于 0.7s 延迟
	await _wait(0.1)
	await _move_to(POS_INSIDE)
	_check(_house._leave_pending == false, "返回区域后延迟判定取消")
	_check(_house._is_inside == true, "返回后保持屋内状态")
	# 等待时间超过完整延迟，确认被取消的计时不会“补切”
	await _wait(DEFAULT_DELAY + 0.2)
	_check(_house._is_inside == true, "取消后即使超过延迟时间也不会补切")


func _test_auto_leave_after_delay() -> void:
	_section("7. 持续离开后自动切回屋外")
	await _move_to(POS_OUTSIDE_NEAR)
	await _wait(DEFAULT_DELAY - 0.2)
	_check(_house._is_inside == true, "延迟结束前仍为屋内")
	await _wait(0.4)
	_check(_house._is_inside == false, "延迟结束后自动切回屋外")
	_check(_house._leave_pending == false, "切换后延迟判定状态复位")
	await _wait(WAIT_TRANSITION)
	_check(_house._exterior_layer.visible == true, "自动出屋后外观图层恢复可见")
	_check(_house._interior_layer_2.visible == false, "自动出屋后室内图层2隐藏")
	_check(_house._interior_layer_3.visible == false, "自动出屋后室内图层3隐藏")
	_check(_house._interior_layer_2.collision_enabled == false, "自动出屋后室内碰撞关闭")
	_check(_npc.visible == false, "自动出屋后 NPC 隐藏")
	_check(_npc._interaction_area.monitoring == false, "自动出屋后 NPC 交互检测禁用")
	_check(_house._player_in_house == false, "区域占用状态为外部")


func _test_no_trigger_when_exterior() -> void:
	_section("8. 屋外状态进出区域不误触发")
	await _move_to(POS_INSIDE)
	await _wait(0.15)
	await _move_to(POS_OUTSIDE)
	await _wait(DEFAULT_DELAY + 0.3)
	_check(_house._is_inside == false, "屋外状态下进出区域不应改变房屋状态")


func _test_rapid_in_out() -> void:
	_section("9. 快速进出（边界抖动）")
	await _enter_house()
	for i in 5:
		await _move_to(POS_OUTSIDE)
		await _wait(0.12)
		_check(_house._is_inside == true, "第%d次短时间离开不应触发切换" % (i + 1))
		await _move_to(POS_INSIDE)
		await _wait(0.12)
		_check(_house._is_inside == true, "第%d次快速返回应保持屋内" % (i + 1))
	# 最后一次离开并停留超过延迟，才允许切回
	await _move_to(POS_OUTSIDE)
	await _wait(DEFAULT_DELAY + 0.3)
	_check(_house._is_inside == false, "最后一次持续离开后才自动切回屋外")


func _test_disable_auto_switch() -> void:
	_section("10. 关闭自动切回开关")
	await _enter_house()
	_house.auto_switch_on_leave = false
	await _move_to(POS_OUTSIDE)
	await _wait(DEFAULT_DELAY + 0.3)
	_check(_house._is_inside == true, "auto_switch_on_leave=false 时离开不自动切换")
	_check(_house._leave_pending == false, "关闭开关时不启动延迟判定")
	await _move_to(POS_INSIDE)
	_house.auto_switch_on_leave = true


func _test_custom_delay() -> void:
	_section("11. 可配置延迟时间")
	_house.leave_delay_seconds = 0.3
	await _move_to(POS_OUTSIDE_NEAR)
	await _wait(0.15)
	_check(_house._is_inside == true, "自定义延迟（0.3s）未到点前不切换")
	_check(_house._leave_pending == true, "自定义延迟判定进行中")
	await _wait(0.3)
	_check(_house._is_inside == false, "自定义延迟到点后自动切回")
	_house.leave_delay_seconds = DEFAULT_DELAY


func _test_polling_fallback() -> void:
	_section("12. 轮询补偿丢失的进出信号")
	await _enter_house()
	# 阻断 body_exited 信号路径，并把轮询间隔临时调大，确定地模拟“信号丢失且轮询未到点”
	_house._house_area.body_exited.disconnect(_house._on_house_body_exited)
	_house.detection_poll_interval = 5.0
	await _move_to(POS_OUTSIDE_NEAR)
	await _wait(0.2)
	_check(_house._player_in_house == true, "离开信号被阻断时占用状态暂时保持旧值")
	# 恢复 0.1s 轮询间隔：下一次复核即纠正占用状态并启动延迟判定
	_house.detection_poll_interval = 0.1
	await _wait(0.25)
	_check(_house._player_in_house == false, "轮询复核应纠正占用状态为外部")
	_check(_house._leave_pending == true, "轮询发现离开后同样启动延迟判定")
	await _wait(DEFAULT_DELAY + 0.3)
	_check(_house._is_inside == false, "仅凭轮询补偿也能完成自动切回屋外")
	# 恢复信号连接供后续用例使用
	_house._house_area.body_exited.connect(_house._on_house_body_exited)


func _test_repeated_cycles() -> void:
	_section("13. 多轮进出端到端循环")
	await _enter_house()
	_check(_house._is_inside == true, "第二轮：门口交互可再次进屋")
	# 在门口再按一次交互键，手动出屋（验证信号订阅在多轮后仍然正常）
	await _move_to(POS_DOOR)
	_check(_house._player_in_range == true, "第二轮：门口交互检测正常")
	Messages.player_interacted.emit(_player)
	await _wait(WAIT_TRANSITION)
	_check(_house._is_inside == false, "第二轮：门口手动出屋正常")
	# 第三轮：进屋后自动出屋
	await _enter_house()
	_check(_house._is_inside == true, "第三轮：进屋正常")
	await _move_to(POS_OUTSIDE)
	await _wait(DEFAULT_DELAY + 0.3)
	_check(_house._is_inside == false, "第三轮：离开自动出屋正常")
	_check(_npc.visible == false, "循环结束后 NPC 恢复隐藏")
	_check(_house._exterior_layer.visible == true, "循环结束后外观图层恢复显示")


func _test_smooth_transition() -> void:
	_section("14. 图层交叉淡变（无屏幕遮罩）")
	# 14.1 静止态：无过渡 tween；房子下不创建任何遮罩节点；图层透明度已复位
	_check(_house._transition_tween == null and _house._transition_anim == null,
		"静止态下不存在过渡 tween")
	_check(_house.get_node_or_null("TransitionLayer") == null, "房子下不创建任何遮罩 CanvasLayer")
	_check(_house.transition_duration == DEFAULT_TRANSITION, "默认交叉淡变时长为 0.24s")
	_check(_house._exterior_layer.modulate.a == 1.0, "静止态外观图层透明度为 1")
	_check(_house._interior_layer_2.modulate.a == 1.0, "静止态（隐藏）内景图层透明度也复位为 1")
	await _move_to(POS_DOOR)

	# 14.2 进屋淡变半程（总时长 0.24s，中点 0.12s）：精确等 3 个物理帧 ≈0.05s，
	# 两组图层 / NPC 必须同时可见且都处于半透明，碰撞 / 遮挡体 / 交互尚未到中点
	Messages.player_interacted.emit(_player)
	for i in 3:
		await get_tree().physics_frame
	var ext_a: float = _house._exterior_layer.modulate.a
	var int_a: float = _house._interior_layer_2.modulate.a
	var npc_a: float = _npc.modulate.a
	_check(_house._exterior_layer.visible == true and _house._interior_layer_2.visible == true
		and _house._interior_layer_3.visible == true, "淡变半程内外景图层同时可见")
	_check(ext_a > 0.05 and ext_a < 0.95 and int_a > 0.05 and int_a < 0.95,
		"外观渐隐(%.2f) 与内景渐现(%.2f) 交叉进行" % [ext_a, int_a])
	_check(_npc.visible == true and npc_a > 0.05 and npc_a < 0.95,
		"NPC 跟随交叉淡变（实际 a=%.2f）" % npc_a)
	_check(_house._interior_layer_2.collision_enabled == false, "中点前内景碰撞不提前开启")
	_check(_house._exterior_occluders[0].visible == true, "中点前外观遮挡体保持原状")
	_check(_npc._interaction_area.monitoring == false, "中点前 NPC 交互不提前启用")
	_check(_npc.is_physics_processing() == false, "淡变期间 NPC 物理冻结（防止无地面坠落）")

	# 14.3 过渡完成：屋内终态，隐藏组透明度复位，tween 全部释放，NPC 物理恢复
	await _await_condition(func() -> bool: return _house._transition_tween == null)
	_check(_house._is_inside == true, "进屋过渡完成")
	_check(_house._exterior_layer.visible == false, "完成后外观图层隐藏")
	_check(_house._exterior_layer.modulate.a == 1.0, "外观隐藏后透明度复位为 1")
	_check(_house._interior_layer_2.visible == true and _house._interior_layer_3.visible == true,
		"完成后内景图层可见")
	_check(_house._interior_layer_2.modulate.a == 1.0, "内景图层透明度为 1")
	_check(_house._interior_layer_2.collision_enabled == true, "完成后内景碰撞开启")
	_check(_house._exterior_occluders[0].visible == false, "完成后外观遮挡体隐藏")
	_check(_npc.visible == true and _npc.modulate.a == 1.0, "完成后 NPC 完全显示")
	_check(_npc._interaction_area.monitoring == true, "完成后 NPC 交互启用")
	_check(_npc.is_physics_processing() == true, "完成后 NPC 物理恢复")
	_check(_house._transition_tween == null and _house._transition_anim == null,
		"完成后过渡 tween 已释放")

	# 14.4 长时长（1.0s，中点 0.5s）出屋：校验中点前后碰撞 / 遮挡体 / 交互的切换时序
	_house.transition_duration = 1.0
	Messages.player_interacted.emit(_player)
	await _wait(0.2)
	_check(_house._is_inside == false, "已请求出屋（标志立即翻转）")
	_check(_house._exterior_layer.visible == true and _house._interior_layer_2.visible == true,
		"中点前两组图层仍同时可见")
	_check(_house._interior_layer_2.collision_enabled == true, "出屋中点前内景碰撞保持开启")
	_check(_house._exterior_occluders[0].visible == false, "出屋中点前遮挡体保持隐藏")
	_check(_npc._interaction_area.monitoring == true, "出屋中点前 NPC 交互保持启用")
	await _wait(0.4) # 累计 0.6s，已过中点
	_check(_house._interior_layer_2.collision_enabled == false, "越过中点后内景碰撞关闭")
	_check(_house._exterior_occluders[0].visible == true, "越过中点后遮挡体恢复")
	_check(_npc._interaction_area.monitoring == false, "越过中点后 NPC 交互禁用")
	_check(_house._interior_layer_2.visible == true, "结束前内景图层仍可见（渐隐中）")
	# 条件等待过渡结束（不死等物理时间，避免无头环境空闲帧调度抖动导致偶发误判）
	await _await_condition(func() -> bool: return _house._transition_tween == null, 1.5)
	_check(_house._exterior_layer.visible == true and _house._exterior_layer.modulate.a == 1.0,
		"长时出屋后外观完全显示")
	_check(_house._interior_layer_2.visible == false and _house._interior_layer_2.modulate.a == 1.0,
		"长时出屋后内景隐藏且透明度复位")
	_check(_house._transition_tween == null, "长时过渡 tween 已释放")
	_house.transition_duration = DEFAULT_TRANSITION

	# 14.5 中途打断：进屋 0.1s（中点 0.3s 未到）后再次交互反向，从当前透明度续接，
	# 结束后状态 / 图层 / 碰撞 / NPC 全部自洽
	_house.transition_duration = 0.6
	Messages.player_interacted.emit(_player)
	await _wait(0.1)
	_check(_house._exterior_layer.visible == true and _house._interior_layer_2.visible == true,
		"打断前两组图层正在交叉淡变")
	_check(_house._interior_layer_2.collision_enabled == false, "打断前碰撞尚未切换")
	Messages.player_interacted.emit(_player)
	await _await_condition(func() -> bool: return _house._transition_tween == null, 1.5)
	_check(_house._is_inside == false, "打断后续接完成，最终为屋外")
	_check(_house._exterior_layer.visible == true and _house._exterior_layer.modulate.a == 1.0,
		"打断结束后外观图层完全可见")
	_check(_house._interior_layer_2.visible == false and _house._interior_layer_3.visible == false,
		"打断结束后内景图层隐藏")
	_check(_house._interior_layer_2.modulate.a == 1.0, "打断结束后内景透明度复位")
	_check(_house._interior_layer_2.collision_enabled == false, "打断结束后内景碰撞关闭")
	_check(_npc.visible == false and _npc.modulate.a == 1.0, "打断结束后 NPC 隐藏且透明度复位")
	_check(_npc.is_physics_processing() == true, "打断结束后 NPC 物理恢复")
	_check(_house._transition_tween == null and _house._transition_anim == null,
		"打断结束后无残留 tween")
	_house.transition_duration = DEFAULT_TRANSITION

	# 14.6 过渡帧耗时采样：统计一次完整进屋交叉淡变期间每帧的真实墙钟耗时
	var stats := await _sample_transition_frames()
	var worst_ms: float = stats["worst_ms"]
	var avg_ms: float = stats["avg_ms"]
	print("  [性能] 过渡采样帧数=%d，平均帧耗时 %.2fms，最差帧耗时 %.2fms（30fps 门槛 33.3ms）"
		% [stats["frames"], avg_ms, worst_ms])
	# 硬性断言只拦“灾难性卡顿”（>100ms）；30fps 门槛作为报告输出，真机 GPU 绘制开销需在设备上复测
	_check(worst_ms < 100.0, "过渡期间无 >100ms 的灾难性卡顿（实测最差 %.2fms）" % worst_ms)
	# 恢复屋外状态收尾
	Messages.player_interacted.emit(_player)
	await _await_condition(func() -> bool: return _house._transition_tween == null)
	_check(_house._is_inside == false, "性能采样后恢复屋外状态")


# ---------- 辅助方法 ----------

## 通过门口交互进入屋内，并等待图层过渡完成
func _enter_house() -> void:
	await _move_to(POS_DOOR)
	Messages.player_interacted.emit(_player)
	await _wait(WAIT_TRANSITION + 0.1)


## 驱动玩家移动到指定世界坐标，等待到达并多留几帧让 Area2D 进出信号派发
func _move_to(pos: Vector2) -> void:
	_move_target = pos
	var dist := (_player.global_position - pos).length()
	var travel_frames := int(ceil(dist / MOVE_SPEED * 60.0))
	# 到达后再等 3 个物理帧：Area2D 进出信号在跨越当步物理刷新后派发，2 帧即可送达，
	# 余量取 3 帧；不能加太多，否则“跨越边界后”的额外等待会吃掉防抖延迟用例的时间预算
	for i in travel_frames + 3:
		await get_tree().physics_frame
	# 理论上必达（无碰撞阻挡）；断言保护，避免静默偏差污染后续用例
	if (_player.global_position - pos).length() > 2.0:
		push_warning("玩家未精确到达 %s，实际 %s" % [pos, _player.global_position])


## 等待指定秒数（按物理帧计，无头模式物理按真实时间约 60Hz 步进）
func _wait(seconds: float) -> void:
	var frame_count := int(ceil(seconds * 60.0)) + 1
	for i in frame_count:
		await get_tree().physics_frame


## 按物理帧轮询直到条件成立（tween 走空闲帧 + 真实时间，直接死等物理秒数在不同
## 管道 / 负载下可能抖动）；超时返回条件的最终值
func _await_condition(condition: Callable, timeout: float = 2.0) -> bool:
	var elapsed := 0.0
	while elapsed < timeout:
		if condition.call():
			return true
		await get_tree().physics_frame
		elapsed += 1.0 / 60.0
	return condition.call()


## 触发一次进屋交叉淡变，并逐渲染帧采样真实墙钟帧耗时（微秒计时），
## 直到过渡 tween 释放并再补 10 帧收尾；返回 frames / avg_ms / worst_ms
func _sample_transition_frames() -> Dictionary:
	Messages.player_interacted.emit(_player)
	var samples: Array[float] = []
	var last_usec := Time.get_ticks_usec()
	var finish_tail := 0
	# 封顶 300 个渲染帧（约 2.5s@120fps），防止异常情况下死循环
	for i in 300:
		await get_tree().process_frame
		var now_usec := Time.get_ticks_usec()
		samples.append(float(now_usec - last_usec) / 1000.0)
		last_usec = now_usec
		if _house._transition_tween == null:
			finish_tail += 1
			if finish_tail >= 10:
				break
		else:
			finish_tail = 0
	var worst := 0.0
	var total := 0.0
	for ms in samples:
		worst = maxf(worst, ms)
		total += ms
	return {
		"frames": samples.size(),
		"avg_ms": total / maxi(samples.size(), 1),
		"worst_ms": worst,
	}


func _section(title: String) -> void:
	print("---------- " + title)


func _check(condition: bool, label: String) -> void:
	if condition:
		_pass += 1
		print("  [PASS] " + label)
	else:
		_fail += 1
		printerr("  [FAIL] " + label)

