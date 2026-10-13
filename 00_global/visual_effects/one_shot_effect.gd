class_name OneShotEffect extends Sprite2D

## 一次性精灵表特效：按整表绝对帧号播放一段帧区间，播到最后一帧后自动销毁。
## 由 VisualEffects.play_effect() 创建并挂到 VisualEffects 下，随 clear_effects() 在切场景时统一清理。

var _first : int = 0
var _last : int = 0
var _fps : float = 14.0
var _elapsed : float = 0.0
var _playing : bool = false


#tex 精灵表贴图；columns/rows 表的网格列数与行数；first_frame/last_frame 整表绝对帧号（行*列+列）
func play( tex : Texture2D , columns : int , rows : int , first_frame : int , last_frame : int , fps : float = 14.0 , scale_mult : float = 1.0 , flip : bool = false ) -> void:
	texture = tex
	hframes = maxi( columns , 1 )
	vframes = maxi( rows , 1 )
	_first = clampi( first_frame , 0 , hframes * vframes - 1 )
	_last = clampi( last_frame , _first , hframes * vframes - 1 )
	_fps = maxf( fps , 0.001 )
	scale = Vector2.ONE * scale_mult
	flip_h = flip
	frame = _first
	_elapsed = 0.0
	_playing = true
	set_process( true )
	pass


func _process( delta : float ) -> void:
	if not _playing:
		return
	_elapsed += delta
	var idx : int = _first + int( _elapsed * _fps )
	if idx >= _last:
		#落在最后一帧即结束：停帧后立即销毁，避免残留一帧停在画面上
		frame = _last
		_playing = false
		set_process( false )
		queue_free()
		return
	frame = idx
	pass