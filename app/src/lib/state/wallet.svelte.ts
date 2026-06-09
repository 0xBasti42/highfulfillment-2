/**
 * Smart-wallet balance state.
 *
 * Source of truth for "how much of each tradeable asset does the user
 * hold". Today the values are stubbed at zero — when the RPC pipeline
 * lands, that pipeline will read balances via viem `multicall` against
 * the smart wallet and push them in via `wallet.setBalance(asset, n)`.
 *
 * Consumers read via `wallet.balanceOf(asset)` and the reactive store
 * triggers any `$derived` filters / renders downstream (e.g. the
 * AccountSidebar's conditional per-asset rows).
 */

import type { DefaultCrypto, Stablecoin } from '$lib/state/settings.svelte';

/* Assets the smart wallet can hold + display in the balance section.
   Combines the crypto + stablecoin unions plus DAI, which isn't
   user-selectable as a default but is a supported tradeable holding. */
export type SupportedAsset = DefaultCrypto | Stablecoin | 'DAI';

/* Canonical display order. Drives the order of conditional balance
   rows when the user holds multiple non-default assets. Crypto first
   (BTC → ETH → SETH), then stablecoins by issuer prominence. */
export const SUPPORTED_ASSETS: readonly SupportedAsset[] = [
	'BTC',
	'ETH',
	'SETH',
	'TGBP',
	'USDC',
	'EURC',
	'DAI'
] as const;

/* Per-asset display precision — NOT chain decimals (BTC is 8, ETH is
   18, USDC is 6, etc). This is purely how many fractional digits to
   show in the UI. Cryptos get 4 (the small-balance use case is
   common), stablecoins get 2 (cents-equivalent). */
export const ASSET_DECIMALS: Record<SupportedAsset, number> = {
	BTC: 4,
	ETH: 4,
	SETH: 4,
	TGBP: 2,
	USDC: 2,
	EURC: 2,
	DAI: 2
};

/* Stubbed balances. Replace with reads from the on-chain RPC pipeline
   once the smart wallet is deployed. The shape (`Record<asset, number>`)
   is intentionally simple — fine for display; if we ever need richer
   per-asset metadata (last-updated timestamp, USD valuation, etc.) we
   can promote to `Record<asset, { balance, ... }>` without changing
   consumer call sites that only use `balanceOf()`. */
let _balances = $state<Record<SupportedAsset, number>>({
	BTC: 0,
	ETH: 0,
	SETH: 0,
	TGBP: 0,
	USDC: 0,
	EURC: 0,
	DAI: 0
});

export const wallet = {
	get balances() {
		return _balances;
	},
	balanceOf(asset: SupportedAsset): number {
		return _balances[asset];
	},
	/* Single-asset setter keeps invalidation surgical — the future RPC
	   sync will call this once per asset whose balance changed, rather
	   than rebuilding the whole record on every poll. */
	setBalance(asset: SupportedAsset, value: number) {
		_balances = { ..._balances, [asset]: value };
	}
};
