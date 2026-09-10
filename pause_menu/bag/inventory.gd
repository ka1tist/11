extends Node
## 背包数据管理器（autoload 单例：Inventory）
## 负责物品的存储、堆叠与增删查询；UI 只负责展示，数据与界面解耦。
##
## 新增物品到游戏中的最简方式：
##   1. 在 pause_menu/bag/items/ 下创建一个 ItemData 资源（设好 id/名称/图标）
##   2. 代码中调用 Inventory.add_item( preload("res://.../xxx.tres"), 数量 )

signal inventory_changed

## 背包格子总数（需与 bag.gd 的网格容量一致）
const SLOT_CAPACITY : int = 20

# 固定长度数组，按下标对应背包格子：ItemData 或 null
var _slots : Array = []
# 与 _slots 平行的数量数组
var _amounts : Array = []


func _ready() -> void:
	# 新游戏背包初始为空；物品全部由游戏内容（如宝箱）发放
	clear( false )
	pass


## 序列化为可写入 JSON 存档的数组（保留每个物品所在格子位置）
func serialize() -> Array:
	var data : Array = []
	for i in SLOT_CAPACITY:
		var item : ItemData = _slots[ i ]
		if item != null and _amounts[ i ] > 0:
			if item.resource_path.is_empty():
				push_warning( "Inventory.serialize：物品 %s 是内置资源无路径，无法存档（请保存为 .tres 文件）" % item.item_name )
				continue
			data.append( {
				"slot" : i ,
				"path" : item.resource_path ,
				"amount" : _amounts[ i ] ,
			} )
	return data


## 从存档数组恢复背包。data 为空（新游戏/旧版本存档）时背包为空。
func deserialize( data : Array ) -> void:
	clear( false )
	if data == null or data.is_empty():
		inventory_changed.emit()
		return
	for entry in data:
		if typeof( entry ) != TYPE_DICTIONARY:
			push_warning( "Inventory.deserialize：跳过非法条目（不是字典）" )
			continue
		var slot_index : int = int( entry.get( "slot" , -1 ) )
		var item_path : String = str( entry.get( "path" , "" ) )
		var amount : int = int( entry.get( "amount" , 0 ) )
		if not _is_valid_slot( slot_index ) or item_path.is_empty() or amount <= 0:
			continue
		var loaded : Resource = load( item_path )
		if loaded == null or not ( loaded is ItemData ):
			push_warning( "Inventory.deserialize：无法加载物品资源 %s，已跳过" % item_path )
			continue
		_slots[ slot_index ] = loaded
		_amounts[ slot_index ] = mini( amount , ( loaded as ItemData ).max_stack )
	inventory_changed.emit()
	pass


## 添加物品（同类自动堆叠，堆满后放入空格）。返回实际放入的数量。
func add_item( item : ItemData , amount : int = 1 ) -> int:
	if item == null:
		push_warning( "Inventory.add_item：物品数据为空，已忽略" )
		return 0
	if amount <= 0:
		push_warning( "Inventory.add_item：数量必须大于0（收到 %d）" % amount )
		return 0
	if item.id == &"":
		push_warning( "Inventory.add_item：物品 %s 缺少有效 id，已忽略" % item.item_name )
		return 0
	var remaining : int = amount
	# 第一遍：堆叠到已有同类格
	for i in SLOT_CAPACITY:
		if remaining <= 0:
			break
		if _slots[ i ] != null and ( _slots[ i ] as ItemData ).id == item.id:
			var room : int = item.max_stack - _amounts[ i ]
			var put : int = mini( remaining , room )
			if put > 0:
				_amounts[ i ] += put
				remaining -= put
	# 第二遍：放入空格
	for i in SLOT_CAPACITY:
		if remaining <= 0:
			break
		if _slots[ i ] == null:
			var put : int = mini( remaining , item.max_stack )
			_slots[ i ] = item
			_amounts[ i ] = put
			remaining -= put
	var added : int = amount - remaining
	if remaining > 0:
		push_warning( "Inventory.add_item：背包已满，%s 剩余 %d 个未放入" % [ item.item_name , remaining ] )
	if added > 0:
		inventory_changed.emit()
	return added


## 移除指定格中的物品（数量不足则全部移除）。返回实际移除数量。
func remove_item_from_slot( slot_index : int , amount : int = 1 ) -> int:
	if not _is_valid_slot( slot_index ) or amount <= 0:
		return 0
	if _slots[ slot_index ] == null:
		return 0
	var removed : int = mini( amount , _amounts[ slot_index ] )
	_amounts[ slot_index ] -= removed
	if _amounts[ slot_index ] <= 0:
		_slots[ slot_index ] = null
		_amounts[ slot_index ] = 0
	inventory_changed.emit()
	return removed


## 查询某物品当前持有总量
func get_item_amount( item_id : StringName ) -> int:
	var total : int = 0
	for i in SLOT_CAPACITY:
		if _slots[ i ] != null and ( _slots[ i ] as ItemData ).id == item_id:
			total += _amounts[ i ]
	return total


## 取指定格的物品数据（空格或越界返回 null）
func get_slot_item( slot_index : int ) -> ItemData:
	if not _is_valid_slot( slot_index ):
		return null
	return _slots[ slot_index ]


## 取指定格的物品数量（越界返回 0）
func get_slot_amount( slot_index : int ) -> int:
	if not _is_valid_slot( slot_index ):
		return 0
	return _amounts[ slot_index ]


## 清空背包
func clear( emit_change : bool = true ) -> void:
	_slots.clear()
	_amounts.clear()
	for i in SLOT_CAPACITY:
		_slots.append( null )
		_amounts.append( 0 )
	if emit_change:
		inventory_changed.emit()
	pass


func _is_valid_slot( slot_index : int ) -> bool:
	if slot_index < 0 or slot_index >= SLOT_CAPACITY:
		push_warning( "Inventory：格子下标 %d 越界（有效范围 0~%d）" % [ slot_index , SLOT_CAPACITY - 1 ] )
		return false
	return true
