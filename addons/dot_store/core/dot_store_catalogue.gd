class_name GSStoreCatalogue
extends RefCounted

## What is for sale: cosmetics, passes and bundles with a price and an optional availability window. Pure data, validated on load.

const KINDS := ["cosmetic", "pass", "bundle"]

var _items: Dictionary = {}


## Build from {"items": [{id, kind, price, contents?, from?, until?, duration?, requires?, sale?: {price, from?, until?}}]}. Times are unix seconds; 0 or absent is open-ended.
static func from_dict(d: Dictionary) -> GSResult:
	var cat := GSStoreCatalogue.new()
	var raw = d.get("items")
	if not (raw is Array):
		return GSResult.fail(GSError.CODE_PARSE, "catalogue needs an items list")
	for it in raw:
		if not (it is Dictionary):
			return GSResult.fail(GSError.CODE_PARSE, "catalogue item is not an object")
		var id := str(it.get("id", ""))
		if id == "":
			return GSResult.fail(GSError.CODE_INVALID, "catalogue item has no id")
		if cat._items.has(id):
			return GSResult.fail(GSError.CODE_CONFLICT, "catalogue id %s is listed twice" % id)
		var kind := str(it.get("kind", ""))
		if not KINDS.has(kind):
			return GSResult.fail(GSError.CODE_INVALID, "item %s has unknown kind %s" % [id, kind])
		var price = it.get("price")
		if not (price is int or (price is float and price == floorf(price))) or int(price) < 0:
			return GSResult.fail(GSError.CODE_INVALID, "item %s price must be a whole number of at least 0" % id)
		var contents: Array = []
		if kind == "bundle":
			var c = it.get("contents")
			if not (c is Array) or c.is_empty():
				return GSResult.fail(GSError.CODE_INVALID, "bundle %s needs contents" % id)
			for x in c:
				contents.append(str(x))
		var duration = it.get("duration", 0)
		if not (duration is int or duration is float) or float(duration) < 0.0:
			return GSResult.fail(GSError.CODE_INVALID, "item %s duration must be seconds, 0 or more" % id)
		var requires: Array = []
		var rq = it.get("requires", [])
		if not (rq is Array):
			return GSResult.fail(GSError.CODE_INVALID, "item %s requires must be a list" % id)
		for x in rq:
			requires.append(str(x))
		var sale: Dictionary = {}
		if it.has("sale"):
			var sd = it["sale"]
			var sp = sd.get("price") if sd is Dictionary else null
			if not (sp is int or (sp is float and sp == floorf(sp))) or int(sp) < 0:
				return GSResult.fail(GSError.CODE_INVALID, "item %s sale needs a whole price of at least 0" % id)
			sale = {"price": int(sp), "from": int(sd.get("from", 0)), "until": int(sd.get("until", 0))}
		cat._items[id] = {"id": id, "kind": kind, "price": int(price), "contents": contents, "from": int(it.get("from", 0)), "until": int(it.get("until", 0)),
			"duration": int(duration), "requires": requires, "sale": sale}
	for id in cat._items:
		for x in cat._items[id]["requires"]:
			if not cat._items.has(x) or x == id:
				return GSResult.fail(GSError.CODE_INVALID, "item %s requires %s, which is not another item in the catalogue" % [id, x])
		for x in cat._items[id]["contents"]:
			if not cat._items.has(x):
				return GSResult.fail(GSError.CODE_INVALID, "bundle %s contains unknown item %s" % [id, x])
		var seen := {}
		if cat._cycle(id, seen):
			return GSResult.fail(GSError.CODE_INVALID, "bundle %s contains itself" % id)
	return GSResult.success(cat)


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


## The price at [param now] (unix seconds): the sale price inside its window, otherwise the list price. -1 for an unknown id.
func price_at(id: String, now: int) -> int:
	if not _items.has(id):
		return -1
	var sale: Dictionary = _items[id]["sale"]
	if not sale.is_empty() and (sale["from"] == 0 or now >= sale["from"]) and (sale["until"] == 0 or now < sale["until"]):
		return int(sale["price"])
	return int(_items[id]["price"])


## Seconds an item's entitlement lasts once granted; 0 is for good.
func duration_of(id: String) -> int:
	return int(_items[id]["duration"]) if _items.has(id) else 0


## Ids that must already be owned before [param id] may be bought.
func requires_of(id: String) -> Array:
	return (_items[id]["requires"] as Array).duplicate() if _items.has(id) else []


## Ids on sale at [param now], sorted.
func available_ids(now: int) -> Array:
	var out: Array = []
	for id in ids():
		if available(id, now):
			out.append(id)
	return out


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
