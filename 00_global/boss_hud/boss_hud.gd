extends CanvasLayer

## BOSS 战斗 HUD：屏幕底部主血条（含延迟残影条、阶段刻度、流光扫过、低血脉冲辉光）
## + 全屏阶段横幅 + 全屏闪光。
## 以脚本 autoload 形式注册（与 Audio/VisualEffects 一致），纯代码构建 UI，无需 .tscn。
## 数据来源唯一：Messages.boss_health_changed / boss_phase_changed / boss_defeated。

#血条几何（内部分辨率 640x360，居中 440 宽，贴屏幕底部）
const BAR_WIDTH : float = 440.0
const BAR_HEIGHT : float = 18.0
const BAR_BORDER : float = 2.0
const BAR_MARGIN_BOTTOM : float = 22.0
const BAR_LEFT : float = ( 640.0 - BAR_WIDTH ) * 0.5
const BAR_TOP : float = 360.0 - BAR_MARGIN_BOTTOM - BAR_HEIGHT
const INNER_WIDTH : float = BAR_WIDTH - BAR_BORDER * 2.0
const INNER_HEIGHT : float = BAR_HEIGHT - BAR_BORDER * 2.0

const COLOR_BORDER := Color( 0.10 , 0.07 , 0.11 , 1.0 )
const COLOR_EMPTY := Color( 0.14 , 0.10 , 0.15 , 1.0 )
const COLOR_FILL := Color( 0.88 , 0.26 , 0.45 , 1.0 )
const COLOR_GHOST := Color( 0.95 , 0.74 , 0.36 , 1.0 )
const COLOR_TICK := Color( 0.04 , 0.03 , 0.05 , 0.85 )
const COLOR_TICK_ACTIVE := Color( 1.0 , 0.95 , 0.7 , 1.0 )
const COLOR_GLOW := Color( 1.0 , 0.25 , 0.45 , 0.26 )
const COLOR_EDGE := Color( 0.55 , 0.22 , 0.32 , 1.0 )

#低血脉冲阈值（进入该比例后血条辉光持续脉动，强化压迫感）
const LOW_HP_RATIO : float = 0.34

#阶段刻度（从满血到 0 的比例位置，与 BOSS 阶段阈值严格对齐：
#BOSS 总血量 24 = 3*8，每损失 8 点切阶段 → 阈值在 16/24 与 8/24 处）
const PHASE_THRESHOLDS : Array[ float ] = [ 16.0 / 24.0 , 8.0 / 24.0 ]

#技能冷却图标（血条左侧）：显示第三阶段组合技的未解锁 / 回充中 / 就绪三态
const SKILL_ICON_SIZE : float = 34.0
const SKILL_ICON_GAP : float = 10.0
const SKILL_ICON_LEFT : float = BAR_LEFT - SKILL_ICON_SIZE - SKILL_ICON_GAP
const SKILL_ICON_TOP : float = BAR_TOP + ( BAR_HEIGHT - SKILL_ICON_SIZE ) * 0.5
#组合技冷却总时长（须与 bosses/scripts/boss.gd 的 SKILL_COOLDOWN_MSEC 一致，用于换算剩余秒数）
const SKILL_COOLDOWN_MSEC : int = 10000
const COLOR_SKILL_LOCKED := Color( 0.32 , 0.28 , 0.36 , 1.0 )
const COLOR_SKILL_COOLING := Color( 0.62 , 0.35 , 0.92 , 1.0 )
const COLOR_SKILL_READY := Color( 1.0 , 0.52 , 0.86 , 1.0 )

#阶段横幅：淡入 / 停留 / 淡出
const BANNER_FADE_IN : float = 0.25
const BANNER_HOLD : float = 1.1
const BANNER_FADE_OUT : float = 0.45

var _root : Control
var _bar : Control
var _glow : ColorRect
var _empty : ColorRect
var _ghost : ColorRect
var _fill_clip : Control
var _fill : ColorRect
var _shine : ColorRect
var _ticks : Array[ ColorRect ] = []
var _name_label : Label
var _hp_label : Label
var _banner : Label
var _flash : ColorRect

var _skill_icon : Control
var _skill_glow : ColorRect
var _skill_fill : ColorRect
var _skill_style : StyleBoxFlat
var _skill_glyph : Label
var _skill_time : Label
var _skill_ready : bool = false
var _skill_unlocked : bool = false

var _max_hp : float = 0.0
var _ghost_tween : Tween
var _banner_tween : Tween
var _flash_tween : Tween
var _shine_tween : Tween
var _glow_tween : Tween
var _glow_color_tween : Tween
var _intro_tween : Tween
var _skill_pulse_tween : Tween
var _skill_pop_tween : Tween


func _ready() -> void:
	layer = 3
	_build_ui()
	reset_hud()
	Messages.boss_health_changed.connect( _on_health_changed )
	Messages.boss_phase_changed.connect( _on_phase_changed )
	Messages.boss_defeated.connect( _on_defeated )
	Messages.boss_skill_cooldown.connect( _on_skill_cooldown )
	SceneManager.load_scene_started.connect( reset_hud )
	pass


#region /// 构建 UI

func _build_ui() -> void:
	_root = Control.new()
	_root.name = "BossHudRoot"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_preset( Control.PRESET_FULL_RECT )
	add_child( _root )

	#血条容器（含名称/数值标签，整体做入场上滑演出）
	_bar = Control.new()
	_bar.name = "BossBar"
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.position = Vector2( BAR_LEFT , BAR_TOP )
	_bar.size = Vector2( BAR_WIDTH , BAR_HEIGHT )
	_root.add_child( _bar )

	#外辉光：血条下方的光晕，低血时脉动
	_glow = ColorRect.new()
	_glow.name = "Glow"
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow.color = COLOR_GLOW
	_glow.position = Vector2( -7.0 , -7.0 )
	_glow.size = Vector2( BAR_WIDTH + 14.0 , BAR_HEIGHT + 14.0 )
	_bar.add_child( _glow )

	#外框：底 + 四周描边
	var frame := Panel.new()
	frame.name = "Frame"
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.set_anchors_preset( Control.PRESET_FULL_RECT )
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = COLOR_BORDER
	frame_style.border_color = COLOR_EDGE
	frame_style.set_border_width_all( int( BAR_BORDER ) )
	frame.add_theme_stylebox_override( "panel" , frame_style )
	_bar.add_child( frame )

	#内区：空槽 → 残影 → 实条（带流光）→ 刻度（按此顺序保证层级）
	var inner_pos := Vector2( BAR_BORDER , BAR_BORDER )
	var inner_size := Vector2( INNER_WIDTH , INNER_HEIGHT )
	_empty = _make_bar_rect( "Empty" , inner_pos , inner_size , COLOR_EMPTY )
	_ghost = _make_bar_rect( "Ghost" , inner_pos , inner_size , COLOR_GHOST )

	#实条用 clip_contents 容器裁切：流光扫过时只出现在剩余血量内
	_fill_clip = Control.new()
	_fill_clip.name = "FillClip"
	_fill_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill_clip.clip_contents = true
	_fill_clip.position = inner_pos
	_fill_clip.size = inner_size
	_bar.add_child( _fill_clip )

	_fill = ColorRect.new()
	_fill.name = "Fill"
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill.color = COLOR_FILL
	_fill.size = inner_size
	_fill_clip.add_child( _fill )

	_shine = ColorRect.new()
	_shine.name = "Shine"
	_shine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shine.color = Color( 1.0 , 1.0 , 1.0 , 0.10 )
	_shine.position = Vector2( -INNER_WIDTH * 0.3 , 0.0 )
	_shine.size = Vector2( INNER_WIDTH * 0.16 , INNER_HEIGHT )
	_fill_clip.add_child( _shine )

	for i in PHASE_THRESHOLDS.size():
		var tick := _make_bar_rect( "Tick%d" % i , Vector2( inner_pos.x + inner_size.x * PHASE_THRESHOLDS[ i ] , inner_pos.y ) , Vector2( 2.0 , inner_size.y ) , COLOR_TICK )
		_ticks.append( tick )

	#BOSS 名称（血条正上方居中）
	_name_label = Label.new()
	_name_label.name = "BossName"
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label.position = Vector2( 0.0 , -19.0 )
	_name_label.size = Vector2( BAR_WIDTH , 16.0 )
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override( "font_size" , 13 )
	_name_label.add_theme_color_override( "font_color" , Color( 1.0 , 0.88 , 0.94 , 1.0 ) )
	_name_label.add_theme_color_override( "font_outline_color" , Color( 0.05 , 0.02 , 0.05 , 1.0 ) )
	_name_label.add_theme_constant_override( "outline_size" , 4 )
	_bar.add_child( _name_label )

	#血量数值（血条内右侧，数值压在条上更紧凑）
	_hp_label = Label.new()
	_hp_label.name = "HpValue"
	_hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_label.position = Vector2( -8.0 , 0.0 )
	_hp_label.size = Vector2( BAR_WIDTH - 8.0 , BAR_HEIGHT )
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hp_label.add_theme_font_size_override( "font_size" , 12 )
	_hp_label.add_theme_color_override( "font_color" , Color( 1.0 , 0.96 , 0.98 , 1.0 ) )
	_hp_label.add_theme_color_override( "font_outline_color" , Color( 0.05 , 0.02 , 0.05 , 1.0 ) )
	_hp_label.add_theme_constant_override( "outline_size" , 5 )
	_bar.add_child( _hp_label )

	#技能冷却图标：置于血条左侧，展示第三阶段组合技的解锁/回充/就绪状态
	_build_skill_icon()

	#全屏阶段横幅
	_banner = Label.new()
	_banner.name = "PhaseBanner"
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.set_anchors_preset( Control.PRESET_FULL_RECT )
	#满屏矩形整体上移 70px：使文字视觉中心落在画面中偏上（360/2-70=110）
	_banner.offset_top = -70.0
	_banner.offset_bottom = -70.0
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override( "font_size" , 26 )
	_banner.add_theme_color_override( "font_outline_color" , Color( 0.04 , 0.02 , 0.05 , 1.0 ) )
	_banner.add_theme_constant_override( "outline_size" , 6 )
	_banner.modulate.a = 0.0
	_root.add_child( _banner )

	#全屏闪光（阶段切换/击杀白闪），置于最上层
	_flash = ColorRect.new()
	_flash.name = "Flash"
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color( 1 , 1 , 1 , 1 )
	_flash.set_anchors_preset( Control.PRESET_FULL_RECT )
	_flash.modulate.a = 0.0
	_root.add_child( _flash )
	pass


func _make_bar_rect( node_name : String , pos : Vector2 , size : Vector2 , color : Color ) -> ColorRect:
	var rect := ColorRect.new()
	rect.name = node_name
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.color = color
	rect.position = pos
	rect.size = size
	_bar.add_child( rect )
	return rect


#技能冷却图标：底槽 + 自下而上的回充条 + 随状态换色的描边 + 字符与剩余秒数
func _build_skill_icon() -> void:
	_skill_icon = Control.new()
	_skill_icon.name = "SkillIcon"
	_skill_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skill_icon.position = Vector2( SKILL_ICON_LEFT , SKILL_ICON_TOP )
	_skill_icon.size = Vector2( SKILL_ICON_SIZE , SKILL_ICON_SIZE )
	#轴心取中心：就绪时的放大演出围绕中心缩放
	_skill_icon.pivot_offset = Vector2( SKILL_ICON_SIZE , SKILL_ICON_SIZE ) * 0.5
	_root.add_child( _skill_icon )

	#外辉光：就绪时脉动
	_skill_glow = ColorRect.new()
	_skill_glow.name = "Glow"
	_skill_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skill_glow.color = Color( COLOR_SKILL_READY.r , COLOR_SKILL_READY.g , COLOR_SKILL_READY.b , 0.55 )
	_skill_glow.position = Vector2( -4.0 , -4.0 )
	_skill_glow.size = Vector2( SKILL_ICON_SIZE + 8.0 , SKILL_ICON_SIZE + 8.0 )
	_skill_glow.modulate.a = 0.0
	_skill_icon.add_child( _skill_glow )

	#底槽
	var inner_size := Vector2( SKILL_ICON_SIZE - 4.0 , SKILL_ICON_SIZE - 4.0 )
	var slot := ColorRect.new()
	slot.name = "Slot"
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.color = COLOR_EMPTY
	slot.position = Vector2( 2.0 , 2.0 )
	slot.size = inner_size
	_skill_icon.add_child( slot )

	#回充条：自下而上按冷却进度增长
	_skill_fill = ColorRect.new()
	_skill_fill.name = "Fill"
	_skill_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skill_fill.color = COLOR_SKILL_LOCKED
	_skill_fill.position = Vector2( 2.0 , 2.0 )
	_skill_fill.size = inner_size
	_skill_icon.add_child( _skill_fill )

	#描边：随状态换色
	_skill_style = StyleBoxFlat.new()
	_skill_style.bg_color = Color( 0.0 , 0.0 , 0.0 , 0.0 )
	_skill_style.border_color = COLOR_SKILL_LOCKED
	_skill_style.set_border_width_all( 2 )
	var frame := Panel.new()
	frame.name = "Frame"
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.set_anchors_preset( Control.PRESET_FULL_RECT )
	frame.add_theme_stylebox_override( "panel" , _skill_style )
	_skill_icon.add_child( frame )

	#图标内字符
	_skill_glyph = Label.new()
	_skill_glyph.name = "Glyph"
	_skill_glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skill_glyph.set_anchors_preset( Control.PRESET_FULL_RECT )
	_skill_glyph.text = "技"
	_skill_glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_skill_glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_skill_glyph.add_theme_font_size_override( "font_size" , 16 )
	_skill_glyph.add_theme_color_override( "font_color" , Color( 1.0 , 0.96 , 0.98 , 1.0 ) )
	_skill_glyph.add_theme_color_override( "font_outline_color" , Color( 0.05 , 0.02 , 0.05 , 1.0 ) )
	_skill_glyph.add_theme_constant_override( "outline_size" , 5 )
	_skill_icon.add_child( _skill_glyph )

	#剩余冷却秒数：仅冷却中显示
	_skill_time = Label.new()
	_skill_time.name = "CooldownSeconds"
	_skill_time.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skill_time.position = Vector2( -2.0 , SKILL_ICON_SIZE - 12.0 )
	_skill_time.size = Vector2( SKILL_ICON_SIZE + 4.0 , 11.0 )
	_skill_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_skill_time.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_skill_time.add_theme_font_size_override( "font_size" , 9 )
	_skill_time.add_theme_color_override( "font_color" , Color( 1.0 , 0.82 , 0.95 , 1.0 ) )
	_skill_time.add_theme_color_override( "font_outline_color" , Color( 0.05 , 0.02 , 0.05 , 1.0 ) )
	_skill_time.add_theme_constant_override( "outline_size" , 4 )
	_skill_time.visible = false
	_skill_icon.add_child( _skill_time )
	pass

#endregion


#region /// 对外接口

#显示血条并进入战斗（max_hp<=0 时按 1 处理避免除零）
func show_bar( boss_name : String , max_hp : float ) -> void:
	_max_hp = maxf( max_hp , 1.0 )
	_name_label.text = boss_name
	_bar.visible = true
	_name_label.visible = true
	_hp_label.visible = true
	_set_fill_ratio( 1.0 )
	_ghost.size.x = _fill_clip.size.x
	for tick in _ticks:
		tick.color = COLOR_TICK
	_set_health_text( _max_hp )
	_stop_low_hp_pulse()
	_glow.color = COLOR_GLOW
	_glow.modulate.a = 1.0
	if _glow_color_tween:
		_glow_color_tween.kill()
		_glow_color_tween = null
	#新一场战斗：技能图标回到"未解锁"态
	_on_skill_cooldown( 0.0 , false , false )
	_start_shine()
	#入场：血条自屏幕下缘上滑 + 淡入
	_bar.pivot_offset = Vector2( BAR_WIDTH * 0.5 , BAR_HEIGHT * 0.5 )
	_bar.position = Vector2( BAR_LEFT , BAR_TOP + 28.0 )
	_bar.modulate.a = 0.0
	if _intro_tween:
		_intro_tween.kill()
	_intro_tween = create_tween()
	_intro_tween.set_parallel( true )
	_intro_tween.tween_property( _bar , "position:y" , BAR_TOP , 0.45 ).set_trans( Tween.TRANS_BACK ).set_ease( Tween.EASE_OUT )
	_intro_tween.tween_property( _bar , "modulate:a" , 1.0 , 0.25 )
	pass


#隐藏血条与数值（BOSS 死亡后 / 切换场景）
func hide_bar() -> void:
	_bar.visible = false
	_name_label.visible = false
	_hp_label.visible = false
	if _skill_icon:
		_skill_icon.visible = false
	if _shine_tween:
		_shine_tween.kill()
		_shine_tween = null
	pass


#完整复位（用于切场景）：清掉所有残留动画与横幅
func reset_hud() -> void:
	if _bar:
		hide_bar()
		_bar.modulate.a = 1.0
		_bar.position = Vector2( BAR_LEFT , BAR_TOP )
		_set_fill_ratio( 1.0 )
		_ghost.size.x = _fill_clip.size.x
		_shine.position.x = -INNER_WIDTH * 0.3
		_glow.color = COLOR_GLOW
		_glow.modulate.a = 1.0
	if _banner:
		_banner.modulate.a = 0.0
	if _flash:
		_flash.modulate.a = 0.0
	if _skill_icon:
		_skill_icon.visible = false
		_skill_icon.scale = Vector2.ONE
		_skill_fill.size.y = SKILL_ICON_SIZE - 4.0
		_skill_fill.position.y = 2.0
		_skill_fill.color = COLOR_SKILL_LOCKED
		_skill_style.border_color = COLOR_SKILL_LOCKED
		_skill_glow.modulate.a = 0.0
		_skill_time.visible = false
	_skill_ready = false
	_skill_unlocked = false
	for tw in [ _ghost_tween , _banner_tween , _flash_tween , _shine_tween , _glow_tween , _glow_color_tween , _intro_tween , _skill_pulse_tween , _skill_pop_tween ]:
		if tw:
			tw.kill()
	_ghost_tween = null
	_banner_tween = null
	_flash_tween = null
	_shine_tween = null
	_glow_tween = null
	_glow_color_tween = null
	_intro_tween = null
	_skill_pulse_tween = null
	_skill_pop_tween = null
	_stop_low_hp_pulse()
	_max_hp = 0.0
	pass


#全屏闪光（阶段切换 / 击杀）
func flash( color : Color = Color.WHITE , peak : float = 0.7 , duration : float = 0.35 ) -> void:
	if _flash_tween:
		_flash_tween.kill()
	_flash.color = color
	_flash.modulate.a = peak
	_flash_tween = create_tween()
	_flash_tween.tween_property( _flash , "modulate:a" , 0.0 , duration ).set_trans( Tween.TRANS_SINE ).set_ease( Tween.EASE_IN )
	pass


#全屏阶段横幅（如 "第二阶段" / "狂暴"）
func show_banner( text : String , color : Color = Color( 1.0 , 0.85 , 0.5 ) ) -> void:
	if _banner_tween:
		_banner_tween.kill()
	_banner.text = text
	_banner.add_theme_color_override( "font_color" , color )
	_banner.scale = Vector2.ONE
	_banner.modulate.a = 0.0
	_banner_tween = create_tween()
	_banner_tween.tween_property( _banner , "modulate:a" , 1.0 , BANNER_FADE_IN )
	_banner_tween.tween_interval( BANNER_HOLD )
	_banner_tween.tween_property( _banner , "modulate:a" , 0.0 , BANNER_FADE_OUT )
	pass

#endregion


#region /// 信号回调

func _on_health_changed( hp : float , max_hp : float ) -> void:
	_max_hp = maxf( max_hp , 1.0 )
	var ratio : float = clampf( hp / _max_hp , 0.0 , 1.0 )
	#主条立即跟随；残影条延迟 0.08s 后用 0.25s 缓动追上，形成掉血拖尾
	_set_fill_ratio( ratio )
	if _ghost_tween:
		_ghost_tween.kill()
	_ghost_tween = create_tween()
	_ghost_tween.tween_property( _ghost , "size:x" , _fill_clip.size.x , 0.25 ).set_delay( 0.08 ) \
		.set_trans( Tween.TRANS_CUBIC ).set_ease( Tween.EASE_OUT )
	_set_health_text( maxf( hp , 0.0 ) )
	#阶段刻度在越过阈值后高亮，提示已进入下一阶段
	for i in PHASE_THRESHOLDS.size():
		_ticks[ i ].color = COLOR_TICK_ACTIVE if ratio <= PHASE_THRESHOLDS[ i ] else COLOR_TICK
	_update_low_hp_pulse( ratio )
	pass


func _on_phase_changed( phase : int , _phase_name : String ) -> void:
	var tint := Color( 1.0 , 0.85 , 0.5 )
	if phase >= 3:
		tint = Color( 1.0 , 0.42 , 0.36 )
	elif phase == 2:
		tint = Color( 1.0 , 0.68 , 0.40 )
	#血条辉光短促染色闪动，呼应阶段切换
	#只驱动 color，不动 modulate:a —— 后者归低血脉冲所有，避免两条补间争用同一属性
	if _glow_color_tween:
		_glow_color_tween.kill()
	_glow_color_tween = create_tween()
	_glow_color_tween.tween_property( _glow , "color" , Color( tint.r , tint.g , tint.b , 0.9 ) , 0.18 )
	_glow_color_tween.tween_property( _glow , "color" , COLOR_GLOW , 0.35 )
	flash( Color( 1 , 1 , 1 , 1 ) , 0.55 , 0.4 )
	pass


func _on_defeated() -> void:
	show_banner( "BOSS 已被击败" , Color( 1.0 , 0.95 , 0.7 ) )
	flash( Color( 1 , 1 , 1 , 1 ) , 0.9 , 0.6 )
	#略作停顿再收起血条，让玩家看到血条清空的过程
	await get_tree().create_timer( 1.2 ).timeout
	hide_bar()
	pass


#组合技冷却状态：未解锁 → 冷却回充（含剩余秒数）→ 就绪（辉光脉动 + 弹一下）
func _on_skill_cooldown( ratio : float , is_ready : bool , unlocked : bool ) -> void:
	if _skill_icon == null:
		return
	#战斗期间保持显示（hide_bar / reset_hud 负责收起）
	_skill_icon.visible = true
	var r : float = clampf( ratio , 0.0 , 1.0 )
	var inner : float = SKILL_ICON_SIZE - 4.0
	#回充条自下而上增长
	_skill_fill.size.y = inner * r
	_skill_fill.position.y = 2.0 + inner * ( 1.0 - r )
	var accent : Color = COLOR_SKILL_LOCKED
	if unlocked:
		accent = COLOR_SKILL_READY if is_ready else COLOR_SKILL_COOLING
	_skill_fill.color = accent
	_skill_style.border_color = accent
	_skill_glyph.modulate.a = 1.0 if unlocked else 0.45

	#冷却中显示剩余秒数
	var cooling : bool = unlocked and not is_ready
	_skill_time.visible = cooling
	if cooling:
		_skill_time.text = "%d" % int( ceil( ( 1.0 - r ) * float( SKILL_COOLDOWN_MSEC ) * 0.001 ) )

	#就绪瞬间弹一下；就绪期间辉光持续脉动，其余状态停止脉动
	if is_ready and not _skill_ready:
		_play_skill_ready_pop( accent )
	if is_ready:
		_start_skill_pulse()
	else:
		_stop_skill_pulse()
	_skill_ready = is_ready
	_skill_unlocked = unlocked
	pass

#endregion


#region /// 内部表现

func _set_fill_ratio( ratio : float ) -> void:
	_fill_clip.size.x = maxf( INNER_WIDTH * ratio , 0.0 )
	pass


#流光：一条高光带按固定节奏自左向右扫过血条（被剩余血量裁切）
func _start_shine() -> void:
	if _shine_tween:
		_shine_tween.kill()
	_shine.position.x = -INNER_WIDTH * 0.3
	_shine_tween = create_tween().set_loops()
	_shine_tween.tween_interval( 0.7 )
	_shine_tween.tween_property( _shine , "position:x" , INNER_WIDTH + 20.0 , 0.9 ) \
		.from( -INNER_WIDTH * 0.3 ).set_trans( Tween.TRANS_SINE ).set_ease( Tween.EASE_IN_OUT )
	pass


#低血时让辉光持续脉动，强化残血压迫感
func _update_low_hp_pulse( ratio : float ) -> void:
	if ratio > 0.0 and ratio <= LOW_HP_RATIO:
		if _glow_tween == null:
			_glow_tween = create_tween().set_loops()
			_glow_tween.tween_property( _glow , "modulate:a" , 0.35 , 0.5 )
			_glow_tween.tween_property( _glow , "modulate:a" , 1.0 , 0.5 )
	else:
		_stop_low_hp_pulse()
	pass


func _stop_low_hp_pulse() -> void:
	if _glow_tween:
		_glow_tween.kill()
		_glow_tween = null
	if _glow:
		_glow.modulate.a = 1.0
	pass


#就绪：外辉光持续脉动，强化"技能可用"的提示
func _start_skill_pulse() -> void:
	if _skill_pulse_tween:
		return
	if _skill_glow:
		_skill_glow.color = Color( COLOR_SKILL_READY.r , COLOR_SKILL_READY.g , COLOR_SKILL_READY.b , 0.55 )
	_skill_pulse_tween = create_tween().set_loops()
	_skill_pulse_tween.tween_property( _skill_glow , "modulate:a" , 1.0 , 0.45 )
	_skill_pulse_tween.tween_property( _skill_glow , "modulate:a" , 0.15 , 0.45 )
	pass


func _stop_skill_pulse() -> void:
	if _skill_pulse_tween:
		_skill_pulse_tween.kill()
		_skill_pulse_tween = null
	if _skill_glow:
		_skill_glow.modulate.a = 0.0
	pass


#就绪瞬间图标放大一下，让"技能已就绪"更容易被注意到
func _play_skill_ready_pop( accent : Color ) -> void:
	if _skill_glow:
		_skill_glow.color = Color( accent.r , accent.g , accent.b , 0.55 )
	if _skill_pop_tween:
		_skill_pop_tween.kill()
	_skill_icon.scale = Vector2.ONE
	_skill_pop_tween = create_tween()
	_skill_pop_tween.tween_property( _skill_icon , "scale" , Vector2( 1.18 , 1.18 ) , 0.12 ) \
		.set_trans( Tween.TRANS_BACK ).set_ease( Tween.EASE_OUT )
	_skill_pop_tween.tween_property( _skill_icon , "scale" , Vector2.ONE , 0.18 )
	pass


func _set_health_text( hp : float ) -> void:
	_hp_label.text = "%d / %d" % [ int( ceil( hp ) ) , int( round( _max_hp ) ) ]
	pass

#endregion
