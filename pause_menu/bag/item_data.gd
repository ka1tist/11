class_name ItemData extends Resource

## 物品静态数据（在编辑器中创建 .tres 资源即可新增物品，无需改代码）
## 用法：新建 Resource -> ItemData，设置 id/名称/图标/堆叠上限


## 物品唯一ID（同名物品堆叠的判定依据）
@export var id : StringName = &""

## 物品显示名称
@export var item_name : String = ""

## 物品图标
@export var icon : Texture2D

## 单格最大堆叠数量
@export_range( 1 , 999 ) var max_stack : int = 99

## 物品描述（预留，供后续 tooltip 使用）
@export_multiline var description : String = ""
