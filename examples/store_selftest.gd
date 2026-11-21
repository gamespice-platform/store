extends Node

## gs-store's headless suite (res://examples/store_selftest.tscn).
## Counts sections run to their last line as well as checks, because a script error aborts a section and not the run.

const EXPECTED_SECTIONS := 5
const EXPECTED_CHECKS := 70

var _passed := 0
var _failed := 0
var _sections := 0


func _ready() -> void:
	print("gs-store")
	_config()
	_catalogue()
	_entitlements()
	_intent()
	_timing()
	print("")
	_check(_sections == EXPECTED_SECTIONS, "every section ran to its last line (%d of %d)" % [_sections, EXPECTED_SECTIONS])
	_check(_passed + _failed == EXPECTED_CHECKS, "and the suite ran all %d of its checks (%d)" % [EXPECTED_CHECKS, _passed + _failed])
	print("%d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _cat_dict() -> Dictionary:
	return {"items": [
		{"id": "skin_a", "kind": "cosmetic", "price": 300},
		{"id": "spray_b", "kind": "cosmetic", "price": 100},
		{"id": "pass_s1", "kind": "pass", "price": 950},
		{"id": "starter", "kind": "bundle", "price": 350, "contents": ["skin_a", "spray_b"]},
		{"id": "mega", "kind": "bundle", "price": 1000, "contents": ["starter", "pass_s1"]},
		{"id": "winter", "kind": "cosmetic", "price": 200, "from": 1000, "until": 2000}]}


func _config() -> void:
	var c := GSStoreConfig.new()
	_check(c.validate().ok, "defaults validate")
	_check(c.max_cart_lines == 0, "cart limit defaults to unlimited")
	c.currency = " "
	_check(not c.validate().ok, "an empty currency is refused")
	c.currency = "coins"
	c.intent_ttl_seconds = -1
	_check(not c.validate().ok, "a negative limit is refused")
	c.intent_ttl_seconds = 60
	var applied := c.apply_dictionary({"currency": "gems", "max_cart_lines": 4})
	_check(applied.size() == 2 and c.currency == "gems" and c.max_cart_lines == 4, "a dictionary layer sets every type", str(applied))
	_check(c.env_prefix() == "GS_STORE_" and c.cli_prefix() == "--store-", "env and command-line prefixes")
	var r := GSStoreConfig.from_files()
	_check(r.ok and r.value is GSStoreConfig, "from_files returns a config")
	_sections += 1


func _catalogue() -> void:
	var r := GSStoreCatalogue.from_dict(_cat_dict())
	_check(r.ok, "a good catalogue loads", str(r.error))
	var cat: GSStoreCatalogue = r.value
	_check(cat.has("skin_a") and not cat.has("nope") and cat.ids().size() == 6, "ids and lookup")
	_check(cat.price_of("pass_s1") == 950 and cat.price_of("nope") == -1, "price lookup, unknown is -1")
	_check(cat.expand("mega") == ["pass_s1", "skin_a", "spray_b"], "a bundle of bundles flattens", str(cat.expand("mega")))
	_check(cat.expand("skin_a") == ["skin_a"], "a plain item expands to itself")
	_check(cat.available("skin_a", 5) and not cat.available("winter", 999) and cat.available("winter", 1000) and not cat.available("winter", 2000), "windows are from-inclusive and until-exclusive")
	_check(not GSStoreCatalogue.from_dict({}).ok, "no items list is a parse failure")
	var dup := _cat_dict()
	dup["items"].append({"id": "skin_a", "kind": "cosmetic", "price": 1})
	_check(GSStoreCatalogue.from_dict(dup).error.code == GSError.CODE_CONFLICT, "a duplicate id is a conflict")
	_check(not GSStoreCatalogue.from_dict({"items": [{"id": "x", "kind": "gun", "price": 1}]}).ok, "an unknown kind is refused")
	_check(not GSStoreCatalogue.from_dict({"items": [{"id": "x", "kind": "cosmetic", "price": -1}]}).ok, "a negative price is refused")
	_check(not GSStoreCatalogue.from_dict({"items": [{"id": "x", "kind": "cosmetic", "price": 1.5}]}).ok, "a fractional price is refused")
	_check(not GSStoreCatalogue.from_dict({"items": [{"id": "b", "kind": "bundle", "price": 1, "contents": ["ghost"]}]}).ok, "a bundle with unknown contents is refused")
	_check(not GSStoreCatalogue.from_dict({"items": [{"id": "b", "kind": "bundle", "price": 1, "contents": []}]}).ok, "an empty bundle is refused")
	_check(not GSStoreCatalogue.from_dict({"items": [{"id": "a", "kind": "bundle", "price": 1, "contents": ["b"]}, {"id": "b", "kind": "bundle", "price": 1, "contents": ["a"]}]}).ok, "a bundle cycle is refused")
	_sections += 1


func _entitlements() -> void:
	var cat: GSStoreCatalogue = GSStoreCatalogue.from_dict(_cat_dict()).value
	var ent := GSStoreEntitlements.create()
	_check(GSStoreEntitlements.validate(ent).ok and not GSStoreEntitlements.validate({"owned": 3}).ok and not GSStoreEntitlements.validate({"owned": [1]}).ok, "validate accepts a list of strings only")
	var g := GSStoreEntitlements.grant(ent, cat, "starter")
	_check(g.ok and g.value["added"] == ["skin_a", "spray_b"], "a bundle grants its contents", str(g.value))
	var ent2: Dictionary = g.value["entitlements"]
	_check(ent["owned"].is_empty() and ent2["owned"] == ["skin_a", "spray_b"], "the input is not modified and owned is sorted")
	var again := GSStoreEntitlements.grant(ent2, cat, "mega")
	_check(again.ok and again.value["added"] == ["pass_s1"], "granting skips what is already owned")
	_check(not GSStoreEntitlements.grant(ent, cat, "ghost").ok, "an unknown item is refused")
	_check(GSStoreEntitlements.owns(ent2, "skin_a") and not GSStoreEntitlements.owns(ent2, "pass_s1"), "owns")
	_check(GSStoreEntitlements.missing(ent2, ["skin_a", "pass_s1"]) == ["pass_s1"], "missing lists what is not owned")
	_check(GSStoreEntitlements.check(ent2, ["skin_a"]).ok, "check passes when owned")
	var c := GSStoreEntitlements.check(ent2, ["pass_s1"])
	_check(not c.ok and c.error.code == GSError.CODE_FORBIDDEN, "check is FORBIDDEN when not owned")
	_sections += 1


func _intent() -> void:
	var cfg := GSStoreConfig.new()
	var cat: GSStoreCatalogue = GSStoreCatalogue.from_dict(_cat_dict()).value
	var ent := GSStoreEntitlements.create()
	var r := GSStoreIntent.build(cfg, cat, ent, "p1", ["spray_b", "skin_a"], 100)
	_check(r.ok, "an intent builds", str(r.error))
	var it: Dictionary = r.value
	_check(it["total"] == 400 and it["lines"].size() == 2 and it["lines"][0]["id"] == "skin_a" and it["currency"] == "coins", "lines are sorted and priced, total adds up")
	_check(it["expires"] == 1000 and not GSStoreIntent.is_expired(it, 999) and GSStoreIntent.is_expired(it, 1000), "an intent expires after the ttl")
	_check(GSStoreIntent.build(cfg, cat, ent, "p1", ["skin_a", "spray_b"], 100).value["id"] == it["id"], "the id is deterministic and order independent")
	_check(GSStoreIntent.build(cfg, cat, ent, "p2", ["skin_a", "spray_b"], 100).value["id"] != it["id"], "another player gets another id")
	cfg.intent_ttl_seconds = 0
	_check(GSStoreIntent.build(cfg, cat, ent, "p1", ["skin_a"], 100).value["expires"] == 0 and not GSStoreIntent.is_expired({"expires": 0}, 99999999), "ttl 0 never expires")
	cfg.intent_ttl_seconds = 900
	_check(GSStoreIntent.build(cfg, cat, ent, "p1", [], 100).error.code == GSError.CODE_INVALID, "an empty cart is refused")
	_check(GSStoreIntent.build(cfg, cat, ent, "p1", ["skin_a", "skin_a"], 100).error.code == GSError.CODE_CONFLICT, "a repeated line is refused")
	_check(not GSStoreIntent.build(cfg, cat, ent, "p1", ["ghost"], 100).ok, "an unknown item is refused")
	_check(GSStoreIntent.build(cfg, cat, ent, "p1", ["winter"], 100).error.code == GSError.CODE_STATE, "an item outside its window is refused")
	_check(GSStoreIntent.build(cfg, cat, ent, "p1", ["winter"], 1500).ok, "inside its window it is sold")
	cfg.max_cart_lines = 1
	_check(GSStoreIntent.build(cfg, cat, ent, "p1", ["skin_a", "spray_b"], 100).error.code == GSError.CODE_QUOTA, "an over-limit cart is refused, not trimmed")
	cfg.max_cart_lines = 0
	var owned: Dictionary = GSStoreEntitlements.grant(ent, cat, "starter").value["entitlements"]
	_check(GSStoreIntent.build(cfg, cat, owned, "p1", ["starter"], 100).error.code == GSError.CODE_CONFLICT, "a fully owned bundle is refused")
	cfg.refuse_owned = false
	_check(GSStoreIntent.build(cfg, cat, owned, "p1", ["starter"], 100).ok, "refuse_owned off allows it")
	cfg.refuse_owned = true
	_check(GSStoreIntent.build(cfg, cat, owned, "p1", ["mega"], 100).ok, "a bundle with something new is still sold")
	cfg.enabled = false
	_check(GSStoreIntent.build(cfg, cat, ent, "p1", ["skin_a"], 100).error.code == GSError.CODE_STATE, "a disabled store builds nothing")
	cfg.enabled = true
	_check(GSStoreIntent.verify(cat, it, 200).ok, "the backbone verifies an honest intent")
	var cheap := it.duplicate(true)
	cheap["lines"][0]["price"] = 1
	_check(GSStoreIntent.verify(cat, cheap, 200).error.code == GSError.CODE_INTEGRITY, "a repriced line is caught")
	var cheap2 := it.duplicate(true)
	cheap2["total"] = 1
	_check(GSStoreIntent.verify(cat, cheap2, 200).error.code == GSError.CODE_INTEGRITY, "a wrong total is caught")
	_check(GSStoreIntent.verify(cat, it, 5000).error.code == GSError.CODE_STATE, "an expired intent is refused")
	var f := GSStoreEntitlements.fulfil(ent, cat, it)
	_check(f.ok and f.value["entitlements"]["owned"] == ["skin_a", "spray_b"], "a settled intent grants its lines")
	# payment details never pass
	_check(GSStoreIntent.check_request({"items": ["a"]}).ok, "a plain request passes")
	_check(GSStoreIntent.check_request({"card_number": "4111"}).error.code == GSError.CODE_FORBIDDEN, "card_number is refused")
	_check(not GSStoreIntent.check_request({"a": {"b": [{"CVV": "123"}]}}).ok, "a nested, upper-case cvv is refused")
	_check(not GSStoreIntent.build(cfg, cat, ent, "p1", ["skin_a"], 100).value.has("card"), "an intent has no payment fields")
	var tainted := it.duplicate(true)
	tainted["iban"] = "DE00"
	_check(GSStoreIntent.verify(cat, tainted, 200).error.code == GSError.CODE_FORBIDDEN, "verify refuses an intent carrying payment detail")
	_sections += 1


func _timing() -> void:
	var d := _cat_dict()
	d["items"].append({"id": "boost", "kind": "pass", "price": 200, "duration": 100, "sale": {"price": 50, "from": 1000, "until": 2000}})
	d["items"].append({"id": "elite", "kind": "cosmetic", "price": 500, "requires": ["skin_a"]})
	var cat: GSStoreCatalogue = GSStoreCatalogue.from_dict(d).value
	_check(cat.price_at("boost", 999) == 200 and cat.price_at("boost", 1000) == 50 and cat.price_at("boost", 2000) == 200 and cat.price_at("ghost", 1) == -1, "the sale price holds inside its window only")
	_check(cat.duration_of("boost") == 100 and cat.duration_of("skin_a") == 0 and cat.requires_of("elite") == ["skin_a"], "duration and requires read back")
	var bad := _cat_dict()
	bad["items"].append({"id": "x", "kind": "cosmetic", "price": 1, "requires": ["nope"]})
	_check(not GSStoreCatalogue.from_dict(bad).ok, "a requirement outside the catalogue is refused")
	var cfg := GSStoreConfig.new()
	var ent := GSStoreEntitlements.create()
	var sale := GSStoreIntent.build(cfg, cat, ent, "p1", ["boost"], 1500)
	_check(sale.ok and sale.value["total"] == 50 and GSStoreIntent.verify(cat, sale.value, 1600).ok, "an intent uses the sale price and verifies")
	var locked := GSStoreIntent.build(cfg, cat, ent, "p1", ["elite"], 1500)
	_check(not locked.ok and locked.error.code == GSError.CODE_FORBIDDEN, "a missing prerequisite is FORBIDDEN")
	var have: Dictionary = GSStoreEntitlements.grant(ent, cat, "skin_a").value["entitlements"]
	_check(GSStoreIntent.build(cfg, cat, have, "p1", ["elite"], 1500).ok, "the prerequisite lets the purchase through")
	var timed: Dictionary = GSStoreEntitlements.grant(ent, cat, "boost", 1500).value["entitlements"]
	_check(GSStoreEntitlements.owns_at(timed, "boost", 1599) and not GSStoreEntitlements.owns_at(timed, "boost", 1600), "a timed item runs out at its expiry")
	_check(GSStoreEntitlements.expiring(timed, 1500, 50).is_empty() and GSStoreEntitlements.expiring(timed, 1560, 50) == ["boost"], "expiring lists what runs out soon")
	var renewed: Dictionary = GSStoreEntitlements.grant(timed, cat, "boost", 1550).value["entitlements"]
	_check(renewed["expires"]["boost"] == 1700, "buying again extends the time")
	var pr := GSStoreEntitlements.prune(timed, 1600)
	_check(not GSStoreEntitlements.owns(pr, "boost") and GSStoreEntitlements.owns(timed, "boost"), "prune drops expired items and leaves the input alone")
	var forever: Dictionary = GSStoreEntitlements.grant(ent, cat, "boost").value["entitlements"]
	_check(GSStoreEntitlements.owns_at(forever, "boost", 99999999), "without a clock a timed item is granted for good")
	var rv := GSStoreEntitlements.revoke(timed, cat, "boost")
	_check(rv.ok and rv.value["removed"] == ["boost"] and not GSStoreEntitlements.owns(rv.value["entitlements"], "boost") and not rv.value["entitlements"]["expires"].has("boost"), "revoke takes an item and its clock back")
	_check(not GSStoreEntitlements.revoke(timed, cat, "ghost").ok, "revoking an unknown item is refused")
	_sections += 1


func _check(ok: bool, what: String, extra: String = "") -> void:
	if ok:
		_passed += 1
		print("  ok    ", what)
	else:
		_failed += 1
		print("  FAIL  ", what, "  ", extra)
