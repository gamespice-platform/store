class_name GSStoreConfig
extends GSConfig

## Every tunable of the store. `cfg/addon/dot_store/*.yml`, `DOT_STORE_*` and `--store-*` layer over these defaults. A zero in a limit means unlimited.

const ADDON := "dot-store"

## Master switch: off, no purchase intent is built.
@export var enabled: bool = true
## Currency code every price is quoted in. Only labels the intent; the backbone prices it.
@export var currency: String = "coins"
## Most lines in one cart; 0 is unlimited. A bigger cart is refused, never trimmed.
@export_range(0, 1000, 1) var max_cart_lines: int = 0
## Seconds an intent stays valid for the backbone to settle; 0 never expires.
@export_range(0, 86400, 1) var intent_ttl_seconds: int = 900
## Refuse an intent for something the player already owns.
@export var refuse_owned: bool = true


func env_prefix() -> String:
	return "DOT_STORE_"


func cli_prefix() -> String:
	return "--store-"


func validate() -> GSResult:
	if currency.strip_edges() == "":
		return GSResult.fail(GSError.CODE_INVALID, "store currency is empty")
	if max_cart_lines < 0 or intent_ttl_seconds < 0:
		return GSResult.fail(GSError.CODE_INVALID, "store limits cannot be negative (0 is unlimited)")
	return GSResult.success(self)


## Defaults, then `cfg/addon/dot_store/*.yml`, then environment and command line.
static func from_files() -> GSResult:
	var cfg := GSStoreConfig.new()
	var files := GSAddonConfig.load_dir(ADDON)
	if not files.ok:
		return files
	cfg.apply_dictionary(files.value as Dictionary, "yml")
	return cfg.load_layered()
