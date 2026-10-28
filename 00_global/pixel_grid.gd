class_name PixelGrid

## 像素网格对齐约束模块（纯静态工具，无需挂节点或注册 autoload）。
##
## 目的：保证「进画面的坐标」永远是整数像素，杜绝亚像素偏移造成的整屏抖动 / 像素边缘闪烁。
## 做法分三层：
## 1) 前提约束：项目必须开着 rendering/2d/snap/snap_2d_transforms_to_pixel，且默认纹理过滤为 Nearest。
##    本模块在启动时校验；对齐开关缺失会补上（渲染器每帧读取该设置，运行期写入立即生效），
##    纹理过滤只告警、不擅自改写——它属于美术参数，改它会连带改变所有贴图的观感。
## 2) 对齐工具：任何要写进 transform / 画布坐标的数值统一走 align() / align_position()，
##    避免各处各写一套 round，出现「有的地方取整、有的地方不取整」。
## 3) 缩放量化：像素画的缩放必须是整数倍（1x/2x/3x…）。非整数缩放会把整数世界坐标乘成小数，
##    像素网格必然错位，故演出镜头的缩放一律过 quantize_zoom()。
##
## 本模块只做约束与校验，不改变任何贴图/材质参数，像素画的硬边特性（Nearest + 无 MSAA）保持原样。

#像素对齐开关（渲染器每帧读取）
const SNAP_TRANSFORMS := "rendering/2d/snap/snap_2d_transforms_to_pixel"
#顶点对齐开关（会把多边形顶点也拉到整数上；默认关闭，开启会改变旋转/缩放贴图的表现，只在需要时启用）
const SNAP_VERTICES := "rendering/2d/snap/snap_2d_vertices_to_pixel"
#默认画布纹理过滤（0 = Nearest，像素画硬边的前提）
const TEXTURE_FILTER := "rendering/textures/canvas_textures/default_texture_filter"
const FILTER_NEAREST : int = 0

#判定「已对齐」时允许的误差：只吸收浮点运算的舍入噪声（1e-4 量级），
#不是「差不多就行」——真的出现 0.5px 亚像素偏移必须判失败
const ALIGN_EPSILON : float = 0.0001


#启动时调用一次：校验并补上硬性前提。可重复调用。
static func ensure_constraints() -> void:
	if not bool( ProjectSettings.get_setting( SNAP_TRANSFORMS , true ) ):
		ProjectSettings.set_setting( SNAP_TRANSFORMS , true )
		push_warning( "PixelGrid: 缺少 %s，已强制开启（否则亚像素坐标会直接进画面）" % SNAP_TRANSFORMS )
	if int( ProjectSettings.get_setting( TEXTURE_FILTER , FILTER_NEAREST ) ) != FILTER_NEAREST:
		push_warning( "PixelGrid: %s 不是 Nearest，像素画会被插值模糊（为保持硬边请改回 0）" % TEXTURE_FILTER )
	pass


#单个数值对齐到最近的整数像素
static func align( value : float ) -> float:
	return roundf( value )


#坐标对齐到最近的整数像素（x/y 各自取整）
static func align_position( p : Vector2 ) -> Vector2:
	return p.round()


static func is_aligned( value : float ) -> bool:
	return absf( value - roundf( value ) ) <= ALIGN_EPSILON


static func is_aligned_position( p : Vector2 ) -> bool:
	return is_aligned( p.x ) and is_aligned( p.y )


#把缩放量化成整数倍（最小 1 倍）：非整数倍缩放会让整数世界坐标映射到小数的屏幕坐标，像素网格必然错位
static func quantize_zoom( zoom_value : Vector2 ) -> Vector2:
	return Vector2(
		maxf( 1.0 , roundf( zoom_value.x ) ) ,
		maxf( 1.0 , roundf( zoom_value.y ) )
	)


#当前缩放是否为整数倍（像素严格对齐的前提之一）
static func is_integer_zoom( zoom_value : Vector2 ) -> bool:
	return zoom_value.x >= 1.0 and is_aligned( zoom_value.x ) and zoom_value.y >= 1.0 and is_aligned( zoom_value.y )


#逐帧对齐校验：返回空字符串表示这一帧完全落在整数像素网格上，否则返回第一处不通过的原因。
#检查的是「实际送进渲染的最终画布变换」，所以震屏 offset、镜头位置、缩放都会被覆盖到。
static func check_frame( viewport : Viewport ) -> String:
	if viewport == null:
		return "viewport 为空"
	var canvas : Transform2D = viewport.get_canvas_transform()
	if not is_aligned_position( canvas.origin ):
		return "画布原点非整数：%s" % canvas.origin
	if not is_aligned_position( canvas.x ) or not is_aligned_position( canvas.y ):
		return "画布缩放/轴向非整数：x=%s y=%s" % [ canvas.x , canvas.y ]
	var cam := viewport.get_camera_2d()
	if cam != null:
		if not is_aligned_position( cam.get_screen_center_position() ):
			return "镜头中心非整数：%s" % cam.get_screen_center_position()
		if not is_aligned_position( cam.offset ):
			return "镜头震屏偏移非整数：%s" % cam.offset
		if not is_integer_zoom( cam.zoom ):
			return "镜头缩放非整数倍：%s" % cam.zoom
	return ""
