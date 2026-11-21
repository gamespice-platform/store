class_name DotStoreIntent
extends RefCounted

## A purchase intent: what a player wants to buy, priced from the catalogue, handed to the backbone to settle. It never carries payment details; any request that does is refused.

## Keys (any case, any depth) that mean payment details. A request containing one is refused.
const PAYMENT_KEYS := ["card", "card_number", "cardnumber", "pan", "cvv", "cvc", "cvv2", "expiry", "exp_month", "exp_year", "iban", "bic", "swift", "routing_number", "account_number", "bank_account", "paypal", "password", "billing", "billing_address", "payment_method", "secret"]


## Fails FORBIDDEN when [param d] holds a payment-detail key anywhere.
static func check_request(d) -> DotResult:
	var bad := _find_payment_key(d)
	if bad != "":
		return DotResult.fail(DotError.CODE_FORBIDDEN, "request carries payment detail '%s'; the store only takes purchase intents" % bad)
	return DotResult.success(true)


static func _find_payment_key(v) -> String:
	if v is Dictionary:
		for k in v:
			if PAYMENT_KEYS.has(str(k).to_lower()):
				return str(k)
			var inner := _find_payment_key(v[k])
			if inner != "":
				return inner
	elif v is Array:
		for x in v:
			var inner := _find_payment_key(x)
			if inner != "":
				return inner
	return ""


## Build an intent for [param item_ids] (one line each). The value is {id, player, currency, lines, total, created, expires}.
static func build(cfg: DotStoreConfig, cat: DotStoreCatalogue, ent: Dictionary, player_id: String, item_ids: Array, now: int) -> DotResult:
	if not cfg.enabled:
		return DotResult.fail(DotError.CODE_STATE, "store is disabled")
	var clean := check_request({"player": player_id, "items": item_ids})
	if not clean.ok:
		return clean
	if player_id == "":
		return DotResult.fail(DotError.CODE_INVALID, "intent needs a player id")
	if item_ids.is_empty():
		return DotResult.fail(DotError.CODE_INVALID, "cart is empty")
	if cfg.max_cart_lines > 0 and item_ids.size() > cfg.max_cart_lines:
		return DotResult.fail(DotError.CODE_QUOTA, "cart has %d lines, over max_cart_lines %d" % [item_ids.size(), cfg.max_cart_lines])
	var lines: Array = []
	var seen := {}
	var total := 0
	for raw in item_ids:
		var id := str(raw)
		if seen.has(id):
			return DotResult.fail(DotError.CODE_CONFLICT, "item %s is in the cart twice" % id)
		seen[id] = true
		if not cat.has(id):
			return DotResult.fail(DotError.CODE_INVALID, "unknown item %s" % id)
		if not cat.available(id, now):
			return DotResult.fail(DotError.CODE_STATE, "item %s is not on sale now" % id)
		if cfg.refuse_owned and DotStoreEntitlements.missing(ent, cat.expand(id)).is_empty():
			return DotResult.fail(DotError.CODE_CONFLICT, "player already owns %s" % id)
		var unmet := DotStoreEntitlements.missing(ent, cat.requires_of(id))
		if not unmet.is_empty():
			return DotResult.fail(DotError.CODE_FORBIDDEN, "item %s needs %s first" % [id, ", ".join(unmet)])
		var price := cat.price_at(id, now)
		lines.append({"id": id, "price": price})
		total += price
	lines.sort_custom(func(a, b): return a["id"] < b["id"])
	var parts: Array = []
	for l in lines:
		parts.append(l["id"])
	var intent := {
		"id": DotHash.sha256_text("%s|%s|%d" % [player_id, ",".join(parts), now]),
		"player": player_id, "currency": cfg.currency, "lines": lines, "total": total,
		"created": now, "expires": now + cfg.intent_ttl_seconds if cfg.intent_ttl_seconds > 0 else 0}
	return DotResult.success(intent)


static func is_expired(intent: Dictionary, now: int) -> bool:
	return int(intent.get("expires", 0)) > 0 and now >= int(intent["expires"])


## The backbone side: re-price an intent against the catalogue and reject a tampered or expired one.
static func verify(cat: DotStoreCatalogue, intent: Dictionary, now: int) -> DotResult:
	var clean := check_request(intent)
	if not clean.ok:
		return clean
	if is_expired(intent, now):
		return DotResult.fail(DotError.CODE_STATE, "intent expired")
	var total := 0
	for l in intent.get("lines", []):
		var id := str(l.get("id", ""))
		var due := cat.price_at(id, int(intent.get("created", now)))
		if not cat.has(id) or int(l.get("price", -1)) != due:
			return DotResult.fail(DotError.CODE_INTEGRITY, "intent line %s does not match the catalogue" % id)
		total += due
	if total != int(intent.get("total", -1)):
		return DotResult.fail(DotError.CODE_INTEGRITY, "intent total %s is not %d" % [str(intent.get("total")), total])
	return DotResult.success(intent)
