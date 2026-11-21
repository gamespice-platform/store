# GameSpice Store

Catalogue, entitlements and purchase intents for cosmetics, passes and bundles. Read the family [CLAUDE.md](../../CLAUDE.md) first. **The distributable is `addons/gs_store/`**; it requires [GameSpice Core](../gs-core) only (`ln -s ../../gs-core/addons/gs_core addons/gs_core`, gitignored).

| Path | What |
| --- | --- |
| `core/gs_store_config.gd` | `GSStoreConfig`: every tunable, `from_files()` |
| `core/gs_store_catalogue.gd` | `GSStoreCatalogue`: items, prices, sale windows (`price_at`), `requires`, `duration`, bundle expansion, validation |
| `core/gs_store_entitlements.gd` | `GSStoreEntitlements`: `{owned, expires}`, grant, revoke, prune, `owns_at`, check, fulfil |
| `core/gs_store_intent.gd` | `GSStoreIntent`: build (sale price, prerequisites), verify, expiry, payment-key refusal |
| `examples/store_selftest.tscn` | the suite |

- **Never touch payment details.** Intents only. `PAYMENT_KEYS` is a denylist checked recursively on every request and on verify; extend it, never loosen it. Do not add a field that could hold a card, bank or billing value.
- **Boundary**: not gs-economy (round buy money), not gs-loadout or gs-user-avatar (they consume entitlements), not gs-progression (names pass rewards; Store sells the pass), not gs-save (storage). No class name overlaps any other addon.
- **No hard caps**: `max_cart_lines` and `intent_ttl_seconds` are 0 = unlimited/never; an over-limit cart fails loudly.
- **Pack rules**: no `uid://`, load by path.
- **Validate**: `--import`, parse every `.gd`, run the suite.
