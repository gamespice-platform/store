extends Node

## dot-store's headless suite (res://examples/store_selftest.tscn).
## Counts sections run to their last line as well as checks, because a script error aborts a section and not the run.

const EXPECTED_SECTIONS := 4
const EXPECTED_CHECKS := 57

var _passed := 0
var _failed := 0
var _sections := 0


func _ready() -> void:
	print("dot-store")
	_config()
	_catalogue()
	_entitlements()
	_intent()
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
	var c := DotStoreConfig.new()
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
	_check(c.env_prefix() == "DOT_STORE_" and c.cli_prefix() == "--store-", "env and command-line prefixes")
	var r := DotStoreConfig.from_files()
	_check(r.ok and r.value is DotStoreConfig, "from_files returns a config")
	_sections += 1


func _catalogue() -> void:
	var r := DotStoreCatalogue.from_dict(_cat_dict())
	_check(r.ok, "a good catalogue loads", str(r.error))
	var cat: DotStoreCatalogue = r.value
	_check(cat.has("skin_a") and not cat.has("nope") and cat.ids().size() == 6, "ids and lookup")
	_check(cat.price_of("pass_s1") == 950 and cat.price_of("nope") == -1, "price lookup, unknown is -1")
	_check(cat.expand("mega") == ["pass_s1", "skin_a", "spray_b"], "a bundle of bundles flattens", str(cat.expand("mega")))
	_check(cat.expand("skin_a") == ["skin_a"], "a plain item expands to itself")
	_check(cat.available("skin_a", 5) and not cat.available("winter", 999) and cat.available("winter", 1000) and not cat.available("winter", 2000), "windows are from-inclusive and until-exclusive")
	_check(not DotStoreCatalogue.from_dict({}).ok, "no items list is a parse failure")
	var dup := _cat_dict()
	dup["items"].append({"id": "skin_a", "kind": "cosmetic", "price": 1})
	_check(DotStoreCatalogue.from_dict(dup).error.code == DotError.CODE_CONFLICT, "a duplicate id is a conflict")
	_check(not DotStoreCatalogue.from_dict({"items": [{"id": "x", "kind": "gun", "price": 1}]}).ok, "an unknown kind is refused")
	_check(not DotStoreCatalogue.from_dict({"items": [{"id": "x", "kind": "cosmetic", "price": -1}]}).ok, "a negative price is refused")
	_check(not DotStoreCatalogue.from_dict({"items": [{"id": "x", "kind": "cosmetic", "price": 1.5}]}).ok, "a fractional price is refused")
	_check(not DotStoreCatalogue.from_dict({"items": [{"id": "b", "kind": "bundle", "price": 1, "contents": ["ghost"]}]}).ok, "a bundle with unknown contents is refused")
	_check(not DotStoreCatalogue.from_dict({"items": [{"id": "b", "kind": "bundle", "price": 1, "contents": []}]}).ok, "an empty bundle is refused")
	_check(not DotStoreCatalogue.from_dict({"items": [{"id": "a", "kind": "bundle", "price": 1, "contents": ["b"]}, {"id": "b", "kind": "bundle", "price": 1, "contents": ["a"]}]}).ok, "a bundle cycle is refused")
	_sections += 1


func _entitlements() -> void:
	var cat: DotStoreCatalogue = DotStoreCatalogue.from_dict(_cat_dict()).value
	var ent := DotStoreEntitlements.create()
	_check(DotStoreEntitlements.validate(ent).ok and not DotStoreEntitlements.validate({"owned": 3}).ok and not DotStoreEntitlements.validate({"owned": [1]}).ok, "validate accepts a list of strings only")
	var g := DotStoreEntitlements.grant(ent, cat, "starter")
	_check(g.ok and g.value["added"] == ["skin_a", "spray_b"], "a bundle grants its contents", str(g.value))
	var ent2: Dictionary = g.value["entitlements"]
	_check(ent["owned"].is_empty() and ent2["owned"] == ["skin_a", "spray_b"], "the input is not modified and owned is sorted")
	var again := DotStoreEntitlements.grant(ent2, cat, "mega")
	_check(again.ok and again.value["added"] == ["pass_s1"], "granting skips what is already owned")
	_check(not DotStoreEntitlements.grant(ent, cat, "ghost").ok, "an unknown item is refused")
	_check(DotStoreEntitlements.owns(ent2, "skin_a") and not DotStoreEntitlements.owns(ent2, "pass_s1"), "owns")
	_check(DotStoreEntitlements.missing(ent2, ["skin_a", "pass_s1"]) == ["pass_s1"], "missing lists what is not owned")
	_check(DotStoreEntitlements.check(ent2, ["skin_a"]).ok, "check passes when owned")
	var c := DotStoreEntitlements.check(ent2, ["pass_s1"])
	_check(not c.ok and c.error.code == DotError.CODE_FORBIDDEN, "check is FORBIDDEN when not owned")
	_sections += 1


func _intent() -> void:
	var cfg := DotStoreConfig.new()
	var cat: DotStoreCatalogue = DotStoreCatalogue.from_dict(_cat_dict()).value
	var ent := DotStoreEntitlements.create()
	var r := DotStoreIntent.build(cfg, cat, ent, "p1", ["spray_b", "skin_a"], 100)
	_check(r.ok, "an intent builds", str(r.error))
	var it: Dictionary = r.value
	_check(it["total"] == 400 and it["lines"].size() == 2 and it["lines"][0]["id"] == "skin_a" and it["currency"] == "coins", "lines are sorted and priced, total adds up")
	_check(it["expires"] == 1000 and not DotStoreIntent.is_expired(it, 999) and DotStoreIntent.is_expired(it, 1000), "an intent expires after the ttl")
	_check(DotStoreIntent.build(cfg, cat, ent, "p1", ["skin_a", "spray_b"], 100).value["id"] == it["id"], "the id is deterministic and order independent")
	_check(DotStoreIntent.build(cfg, cat, ent, "p2", ["skin_a", "spray_b"], 100).value["id"] != it["id"], "another player gets another id")
	cfg.intent_ttl_seconds = 0
	_check(DotStoreIntent.build(cfg, cat, ent, "p1", ["skin_a"], 100).value["expires"] == 0 and not DotStoreIntent.is_expired({"expires": 0}, 99999999), "ttl 0 never expires")
	cfg.intent_ttl_seconds = 900
	_check(DotStoreIntent.build(cfg, cat, ent, "p1", [], 100).error.code == DotError.CODE_INVALID, "an empty cart is refused")
	_check(DotStoreIntent.build(cfg, cat, ent, "p1", ["skin_a", "skin_a"], 100).error.code == DotError.CODE_CONFLICT, "a repeated line is refused")
	_check(not DotStoreIntent.build(cfg, cat, ent, "p1", ["ghost"], 100).ok, "an unknown item is refused")
	_check(DotStoreIntent.build(cfg, cat, ent, "p1", ["winter"], 100).error.code == DotError.CODE_STATE, "an item outside its window is refused")
	_check(DotStoreIntent.build(cfg, cat, ent, "p1", ["winter"], 1500).ok, "inside its window it is sold")
	cfg.max_cart_lines = 1
	_check(DotStoreIntent.build(cfg, cat, ent, "p1", ["skin_a", "spray_b"], 100).error.code == DotError.CODE_QUOTA, "an over-limit cart is refused, not trimmed")
	cfg.max_cart_lines = 0
	var owned: Dictionary = DotStoreEntitlements.grant(ent, cat, "starter").value["entitlements"]
	_check(DotStoreIntent.build(cfg, cat, owned, "p1", ["starter"], 100).error.code == DotError.CODE_CONFLICT, "a fully owned bundle is refused")
	cfg.refuse_owned = false
	_check(DotStoreIntent.build(cfg, cat, owned, "p1", ["starter"], 100).ok, "refuse_owned off allows it")
	cfg.refuse_owned = true
	_check(DotStoreIntent.build(cfg, cat, owned, "p1", ["mega"], 100).ok, "a bundle with something new is still sold")
	cfg.enabled = false
	_check(DotStoreIntent.build(cfg, cat, ent, "p1", ["skin_a"], 100).error.code == DotError.CODE_STATE, "a disabled store builds nothing")
	cfg.enabled = true
	_check(DotStoreIntent.verify(cat, it, 200).ok, "the backbone verifies an honest intent")
	var cheap := it.duplicate(true)
	cheap["lines"][0]["price"] = 1
	_check(DotStoreIntent.verify(cat, cheap, 200).error.code == DotError.CODE_INTEGRITY, "a repriced line is caught")
	var cheap2 := it.duplicate(true)
	cheap2["total"] = 1
	_check(DotStoreIntent.verify(cat, cheap2, 200).error.code == DotError.CODE_INTEGRITY, "a wrong total is caught")
	_check(DotStoreIntent.verify(cat, it, 5000).error.code == DotError.CODE_STATE, "an expired intent is refused")
	var f := DotStoreEntitlements.fulfil(ent, cat, it)
	_check(f.ok and f.value["entitlements"]["owned"] == ["skin_a", "spray_b"], "a settled intent grants its lines")
	# payment details never pass
	_check(DotStoreIntent.check_request({"items": ["a"]}).ok, "a plain request passes")
	_check(DotStoreIntent.check_request({"card_number": "4111"}).error.code == DotError.CODE_FORBIDDEN, "card_number is refused")
	_check(not DotStoreIntent.check_request({"a": {"b": [{"CVV": "123"}]}}).ok, "a nested, upper-case cvv is refused")
	_check(not DotStoreIntent.build(cfg, cat, ent, "p1", ["skin_a"], 100).value.has("card"), "an intent has no payment fields")
	var tainted := it.duplicate(true)
	tainted["iban"] = "DE00"
	_check(DotStoreIntent.verify(cat, tainted, 200).error.code == DotError.CODE_FORBIDDEN, "verify refuses an intent carrying payment detail")
	_sections += 1


func _check(ok: bool, what: String, extra: String = "") -> void:
	if ok:
		_passed += 1
		print("  ok    ", what)
	else:
		_failed += 1
		print("  FAIL  ", what, "  ", extra)
