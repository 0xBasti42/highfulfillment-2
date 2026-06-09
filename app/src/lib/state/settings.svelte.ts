/**
 * Per-device user preferences.
 *
 * Persisted to localStorage rather than to Turnkey or chain because
 * these are display/UX choices that legitimately differ between
 * devices (a user might want USD defaults on desktop and TGBP on their
 * phone). If we ever need cross-device sync, we can migrate the
 * relevant keys to Turnkey user tags without touching the call sites.
 *
 * Same singleton pattern as the other state stores so consumers read
 * `settings.defaultStablecoin` and write via `settings.setX(...)`
 * — no `update` callbacks, no direct mutation.
 */

import { browser } from '$app/environment';

export type Stablecoin = 'USDC' | 'TGBP' | 'EURC';
export type EthVariant = 'ETH' | 'SETH';

const STORAGE_KEY_STABLECOIN = 'hp:defaultStablecoin';
const STORAGE_KEY_ETH_VARIANT = 'hp:defaultEthVariant';

/* Default tilted to TGBP rather than USDC: EPL is GBP-denominated at
   source, and the asset-class identity of the platform leans into that.
   Userspace settings UI lets users pick a different default on first
   open if they prefer. */
const DEFAULT_STABLECOIN: Stablecoin = 'TGBP';
/* Default to plain ETH because most users land here knowing what ETH
   is; SETH is the protocol-internal stability wrapper and is opt-in
   once the user understands its role. */
const DEFAULT_ETH_VARIANT: EthVariant = 'ETH';

function isStablecoin(value: unknown): value is Stablecoin {
	return value === 'USDC' || value === 'TGBP' || value === 'EURC';
}

function isEthVariant(value: unknown): value is EthVariant {
	return value === 'ETH' || value === 'SETH';
}

/* Defensive read: localStorage values are user-tamperable strings, so
   we validate before trusting. Falls through to the default if storage
   is unavailable (SSR, privacy mode, quota error). */
function loadStablecoin(): Stablecoin {
	if (!browser) return DEFAULT_STABLECOIN;
	try {
		const stored = localStorage.getItem(STORAGE_KEY_STABLECOIN);
		if (isStablecoin(stored)) return stored;
	} catch {
		/* localStorage can throw in some sandboxed contexts. */
	}
	return DEFAULT_STABLECOIN;
}

function loadEthVariant(): EthVariant {
	if (!browser) return DEFAULT_ETH_VARIANT;
	try {
		const stored = localStorage.getItem(STORAGE_KEY_ETH_VARIANT);
		if (isEthVariant(stored)) return stored;
	} catch {
		/* see loadStablecoin */
	}
	return DEFAULT_ETH_VARIANT;
}

let _defaultStablecoin = $state<Stablecoin>(loadStablecoin());
let _defaultEthVariant = $state<EthVariant>(loadEthVariant());

export const settings = {
	get defaultStablecoin() {
		return _defaultStablecoin;
	},
	setDefaultStablecoin(value: Stablecoin) {
		_defaultStablecoin = value;
		if (!browser) return;
		try {
			localStorage.setItem(STORAGE_KEY_STABLECOIN, value);
		} catch {
			/* Quota / privacy mode failures shouldn't break the UI;
			   the in-memory state still updates for this session. */
		}
	},
	get defaultEthVariant() {
		return _defaultEthVariant;
	},
	setDefaultEthVariant(value: EthVariant) {
		_defaultEthVariant = value;
		if (!browser) return;
		try {
			localStorage.setItem(STORAGE_KEY_ETH_VARIANT, value);
		} catch {
			/* see setDefaultStablecoin */
		}
	}
};
