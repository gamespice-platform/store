class_name DotStoreEntitlements
extends RefCounted

## What a player owns, as a small Dictionary {owned: [ids]} a server can check. Pure functions; the caller owns where it lives.


static func create() -> Dictionary:
	return {"owned": []}


static func validate(ent: Dictionary) -> DotResult:
	if not (ent.get("owned") is Array):
		return DotResult.fail(DotError.CODE_INVALID, "entitlements owned must be a list")
	for x in ent["owned"]:
		if not (x is String):
			return DotResult.fail(DotError.CODE_INVALID, "entitlements owned entries must be strings")
	return DotResult.success(ent)


static func owns(ent: Dictionary, id: String) -> bool:
	return (ent.get("owned", []) as Array).has(id)


## Ids from [param ids] the player does not own yet.
static func missing(ent: Dictionary, ids: Array) -> Array:
	var out: Array = []
	for id in ids:
		if not owns(ent, str(id)):
			out.append(str(id))
	return out


## The server-side gate: ok when the player owns every id, otherwise FORBIDDEN naming what is missing.
static func check(ent: Dictionary, ids: Array) -> DotResult:
	var m := missing(ent, ids)
	if m.is_empty():
		return DotResult.success(true)
	return DotResult.fail(DotError.CODE_FORBIDDEN, "not owned: %s" % ", ".join(m))


## Grant one catalogue item (a bundle grants its contents). The value is {entitlements, added}; the input is not modified.
static func grant(ent: Dictionary, cat: DotStoreCatalogue, id: String) -> DotResult:
	if not cat.has(id):
		return DotResult.fail(DotError.CODE_INVALID, "unknown item %s" % id)
	var ok := validate(ent)
	if not ok.ok:
		return ok
	var next := ent.duplicate(true)
	var added: Array = []
	for x in cat.expand(id):
		if not (next["owned"] as Array).has(x):
			next["owned"].append(x)
			added.append(x)
	next["owned"].sort()
	return DotResult.success({"entitlements": next, "added": added})


## Apply a settled purchase intent: grant every line. Fails whole if any line is unknown.
static func fulfil(ent: Dictionary, cat: DotStoreCatalogue, intent: Dictionary) -> DotResult:
	var cur := ent
	var added: Array = []
	for line in intent.get("lines", []):
		var g := grant(cur, cat, str(line.get("id", "")))
		if not g.ok:
			return g
		cur = g.value["entitlements"]
		added.append_array(g.value["added"])
	return DotResult.success({"entitlements": cur, "added": added})
