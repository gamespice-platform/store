# GameSpice Store

Catalogue, entitlements and purchase intents for cosmetics, passes and bundles. Read the family [CLAUDE.md](../../CLAUDE.md) first. **The distributable is `addons/dot_store/`**; it requires [GameSpice Core](../dot-core) only (`ln -s ../../dot-core/addons/dot_core addons/dot_core`, gitignored).

| Path | What |
| --- | --- |
| `core/dot_store_config.gd` | `GSStoreConfig`: every tunable, `from_files()` |
| `core/dot_store_catalogue.gd` | `GSStoreCatalogue`: items, prices, sale windows (`price_at`), `requires`, `duration`, bundle expansion, validation |
| `core/dot_store_entitlements.gd` | `GSStoreEntitlements`: `{owned, expires}`, grant, revoke, prune, `owns_at`, check, fulfil |
| `core/dot_store_intent.gd` | `GSStoreIntent`: build (sale price, prerequisites), verify, expiry, payment-key refusal |
| `examples/store_selftest.tscn` | the suite |

- **Never touch payment details.** Intents only. `PAYMENT_KEYS` is a denylist checked recursively on every request and on verify; extend it, never loosen it. Do not add a field that could hold a card, bank or billing value.
- **Boundary**: not dot-economy (round buy money), not dot-loadout or dot-user-avatar (they consume entitlements), not dot-progression (names pass rewards; Store sells the pass), not dot-save (storage). No class name overlaps any other addon.
- **No hard caps**: `max_cart_lines` and `intent_ttl_seconds` are 0 = unlimited/never; an over-limit cart fails loudly.
- **Pack rules**: no `uid://`, load by path.
- **Validate**: `--import`, parse every `.gd`, run the suite.
