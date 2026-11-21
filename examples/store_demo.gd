extends SceneTree

## Run: godot --headless --script res://examples/store_demo.gd
## A small shop: a sale, a prerequisite, a timed boost, then a refund. No payment data anywhere.

func _init() -> void:
	var cat: GSStoreCatalogue = GSStoreCatalogue.from_dict({"items": [
		{"id": "skin_a", "kind": "cosmetic", "price": 300},
		{"id": "elite", "kind": "cosmetic", "price": 500, "requires": ["skin_a"]},
		{"id": "boost", "kind": "pass", "price": 200, "duration": 3600, "sale": {"price": 50, "from": 1000, "until": 2000}},
	]}).value
	var cfg := GSStoreConfig.new()
	var ent := GSStoreEntitlements.create()
	print("elite first: ", GSStoreIntent.build(cfg, cat, ent, "p1", ["elite"], 1500).error)
	var intent: Dictionary = GSStoreIntent.build(cfg, cat, ent, "p1", ["boost"], 1500).value
	print("boost on sale, total ", intent["total"])
	ent = GSStoreEntitlements.fulfil(ent, cat, intent, 1500).value["entitlements"]
	print("owns boost at 4000: ", GSStoreEntitlements.owns_at(ent, "boost", 4000), ", at 5100: ", GSStoreEntitlements.owns_at(ent, "boost", 5100))
	print("refund: ", GSStoreEntitlements.revoke(ent, cat, "boost").value["removed"])
	quit()
