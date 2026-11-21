class_name DotStoreCatalogue
extends RefCounted

## What is for sale: cosmetics, passes and bundles with a price and an optional availability window. Pure data, validated on load.

const KINDS := ["cosmetic", "pass", "bundle"]

var _items: Dictionary = {}


## Build from {"items": [{id, kind, price, contents?, from?, until?}]}. Times are unix seconds; 0 or absent is open-ended.
static func from_dict(d: Dictionary) -> DotResult:
	var cat := DotStoreCatalogue.new()
	var raw = d.get("items")
	if not (raw is Array):
		return DotResult.fail(DotError.CODE_PARSE, "catalogue needs an items list")
	for it in raw:
		if not (it is Dictionary):
			return DotResult.fail(DotError.CODE_PARSE, "catalogue item is not an object")
		var id := str(it.get("id", ""))
		if id == "":
			return DotResult.fail(DotError.CODE_INVALID, "catalogue item has no id")
		if cat._items.has(id):
			return DotResult.fail(DotError.CODE_CONFLICT, "catalogue id %s is listed twice" % id)
		var kind := str(it.get("kind", ""))
		if not KINDS.has(kind):
			return DotResult.fail(DotError.CODE_INVALID, "item %s has unknown kind %s" % [id, kind])
		var price = it.get("price")
		if not (price is int or (price is float and price == floorf(price))) or int(price) < 0:
			return DotResult.fail(DotError.CODE_INVALID, "item %s price must be a whole number of at least 0" % id)
		var contents: Array = []
		if kind == "bundle":
			var c = it.get("contents")
			if not (c is Array) or c.is_empty():
				return DotResult.fail(DotError.CODE_INVALID, "bundle %s needs contents" % id)
			for x in c:
				contents.append(str(x))
		cat._items[id] = {"id": id, "kind": kind, "price": int(price), "contents": contents, "from": int(it.get("from", 0)), "until": int(it.get("until", 0))}
	for id in cat._items:
		for x in cat._items[id]["contents"]:
			if not cat._items.has(x):
				return DotResult.fail(DotError.CODE_INVALID, "bundle %s contains unknown item %s" % [id, x])
		var seen := {}
		if cat._cycle(id, seen):
			return DotResult.fail(DotError.CODE_INVALID, "bundle %s contains itself" % id)
	return DotResult.success(cat)


func _cycle(id: String, path: Dictionary) -> bool:
	if path.has(id):
		return true
	path[id] = true
	for x in _items[id]["contents"]:
		if _cycle(x, path.duplicate()):
			return true
	return false


func has(id: String) -> bool:
	return _items.has(id)


func get_item(id: String) -> Dictionary:
	return (_items[id] as Dictionary).duplicate(true) if _items.has(id) else {}


func ids() -> Array:
	var out := _items.keys()
	out.sort()
	return out


func price_of(id: String) -> int:
	return int(_items[id]["price"]) if _items.has(id) else -1


## True when [param now] (unix seconds) is inside the item's window.
func available(id: String, now: int) -> bool:
	if not _items.has(id):
		return false
	var it: Dictionary = _items[id]
	return (it["from"] == 0 or now >= it["from"]) and (it["until"] == 0 or now < it["until"])


## The non-bundle items an id grants, bundles flattened, sorted and unique.
func expand(id: String) -> Array:
	var out := {}
	_expand(id, out)
	var keys := out.keys()
	keys.sort()
	return keys


func _expand(id: String, out: Dictionary) -> void:
	if not _items.has(id):
		return
	if _items[id]["kind"] == "bundle":
		for x in _items[id]["contents"]:
			_expand(x, out)
	else:
		out[id] = true
