class_name GSStoreEntitlements
extends RefCounted

## What a player owns, as a small Dictionary {owned: [ids], expires: {id: unix seconds}} a server can check; `expires` only lists timed items. Pure functions; the caller owns where it lives.


static func create() -> Dictionary:
	return {"owned": [], "expires": {}}


static func validate(ent: Dictionary) -> GSResult:
	if not (ent.get("owned") is Array):
		return GSResult.fail(GSError.CODE_INVALID, "entitlements owned must be a list")
	for x in ent["owned"]:
		if not (x is String):
			return GSResult.fail(GSError.CODE_INVALID, "entitlements owned entries must be strings")
	return GSResult.success(ent)


static func owns(ent: Dictionary, id: String) -> bool:
	return (ent.get("owned", []) as Array).has(id)


## True when the player owns [param id] and it has not run out at [param now].
static func owns_at(ent: Dictionary, id: String, now: int) -> bool:
	if not owns(ent, id):
		return false
	var until := int((ent.get("expires", {}) as Dictionary).get(id, 0))
	return until == 0 or now < until


## Entitlements with everything that ran out by [param now] removed. The input is not modified.
static func prune(ent: Dictionary, now: int) -> Dictionary:
	var next := ent.duplicate(true)
	var exp: Dictionary = next.get("expires", {})
	for id in exp.keys():
		if int(exp[id]) > 0 and now >= int(exp[id]):
			(next["owned"] as Array).erase(id)
			exp.erase(id)
	next["expires"] = exp
	return next


## Timed ids that run out within [param within] seconds of [param now], soonest first.
static func expiring(ent: Dictionary, now: int, within: int) -> Array:
	var out: Array = []
	var exp: Dictionary = ent.get("expires", {})
	for id in exp:
		if (ent.get("owned", []) as Array).has(id) and int(exp[id]) > now and int(exp[id]) - now <= within:
			out.append(str(id))
	out.sort_custom(func(a, b): return int(exp[a]) < int(exp[b]))
	return out


## Takes an item back (a refund): its expanded contents leave the owned list. The value is {entitlements, removed}; the input is not modified.
static func revoke(ent: Dictionary, cat: GSStoreCatalogue, id: String) -> GSResult:
	if not cat.has(id):
		return GSResult.fail(GSError.CODE_INVALID, "unknown item %s" % id)
	var ok := validate(ent)
	if not ok.ok:
		return ok
	var next := ent.duplicate(true)
	var exp: Dictionary = next.get("expires", {})
	var removed: Array = []
	for x in cat.expand(id):
		if (next["owned"] as Array).has(x):
			(next["owned"] as Array).erase(x)
			exp.erase(x)
			removed.append(x)
	next["expires"] = exp
	return GSResult.success({"entitlements": next, "removed": removed})


## Ids from [param ids] the player does not own yet.
static func missing(ent: Dictionary, ids: Array) -> Array:
	var out: Array = []
	for id in ids:
		if not owns(ent, str(id)):
			out.append(str(id))
	return out


## The server-side gate: ok when the player owns every id, otherwise FORBIDDEN naming what is missing.
static func check(ent: Dictionary, ids: Array) -> GSResult:
	var m := missing(ent, ids)
	if m.is_empty():
		return GSResult.success(true)
	return GSResult.fail(GSError.CODE_FORBIDDEN, "not owned: %s" % ", ".join(m))


## Grant one catalogue item (a bundle grants its contents). The value is {entitlements, added}; the input is not modified.
static func grant(ent: Dictionary, cat: GSStoreCatalogue, id: String, now: int = 0) -> GSResult:
	if not cat.has(id):
		return GSResult.fail(GSError.CODE_INVALID, "unknown item %s" % id)
	var ok := validate(ent)
	if not ok.ok:
		return ok
	var next := ent.duplicate(true)
	var added: Array = []
	var exp: Dictionary = next.get("expires", {})
	for x in cat.expand(id):
		var span := cat.duration_of(x)
		if not (next["owned"] as Array).has(x):
			next["owned"].append(x)
			added.append(x)
			if span > 0 and now > 0:
				exp[x] = now + span
		elif span > 0 and now > 0 and exp.has(x):
			exp[x] = maxi(int(exp[x]), now) + span
	next["expires"] = exp
	next["owned"].sort()
	return GSResult.success({"entitlements": next, "added": added})


## Apply a settled purchase intent: grant every line. Fails whole if any line is unknown.
## [param now] (unix seconds) starts the clock of timed items; 0 grants them for good.
static func fulfil(ent: Dictionary, cat: GSStoreCatalogue, intent: Dictionary, now: int = 0) -> GSResult:
	var cur := ent
	var added: Array = []
	for line in intent.get("lines", []):
		var g := grant(cur, cat, str(line.get("id", "")), now)
		if not g.ok:
			return g
		cur = g.value["entitlements"]
		added.append_array(g.value["added"])
	return GSResult.success({"entitlements": cur, "added": added})
