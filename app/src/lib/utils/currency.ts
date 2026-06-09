/**
 * Display metadata for each supported default stablecoin.
 *
 * `sign` is the currency symbol used as a value prefix (e.g. `£ 12.34`).
 * `code` is the three-letter ISO-ish identifier used in labels
 * (e.g. `Price GBP`).
 *
 * Centralised here so any surface that needs to render a monetary
 * figure or fiat label reads from the same source — TokenInfo,
 * AccountSidebar balance, search exchange-rate labels, etc.
 */

import type { Stablecoin } from '$lib/state/settings.svelte';

export type CurrencyDisplay = { sign: string; code: string };

const CURRENCY_BY_STABLECOIN: Record<Stablecoin, CurrencyDisplay> = {
	TGBP: { sign: '£', code: 'GBP' },
	USDC: { sign: '$', code: 'USD' },
	EURC: { sign: '€', code: 'EUR' }
};

export function currencyOf(stablecoin: Stablecoin): CurrencyDisplay {
	return CURRENCY_BY_STABLECOIN[stablecoin];
}
