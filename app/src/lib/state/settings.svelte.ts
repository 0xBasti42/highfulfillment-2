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
export type DefaultCrypto = 'BTC' | 'ETH' | 'SETH';

const STORAGE_KEY_STABLECOIN = 'hp:defaultStablecoin';
const STORAGE_KEY_CRYPTO = 'hp:defaultCrypto';
/* Legacy key used before the type was broadened from `EthVariant` →
   `DefaultCrypto`. Read once on load so existing dev/test users keep
   their preference, then deleted. */
const STORAGE_KEY_CRYPTO_LEGACY = 'hp:defaultEthVariant';

/* Default tilted to TGBP rather than USDC: EPL is GBP-denominated at
   source, and the asset-class identity of the platform leans into that.
   Userspace settings UI lets users pick a different default on first
   open if they prefer. */
const DEFAULT_STABLECOIN: Stablecoin = 'TGBP';
/* Default to plain ETH because most users land here knowing what ETH
   is; SETH is the protocol-internal stability wrapper and BTC requires
   bridging in (we surface Coinbase Wrapped BTC), so both are opt-in
   once the user understands them. */
const DEFAULT_CRYPTO: DefaultCrypto = 'ETH';

function isStablecoin(value: unknown): value is Stablecoin {
	return value === 'USDC' || value === 'TGBP' || value === 'EURC';
}

function isCrypto(value: unknown): value is DefaultCrypto {
	return value === 'BTC' || value === 'ETH' || value === 'SETH';
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

function loadCrypto(): DefaultCrypto {
	if (!browser) return DEFAULT_CRYPTO;
	try {
		const stored = localStorage.getItem(STORAGE_KEY_CRYPTO);
		if (isCrypto(stored)) return stored;
		/* Transparent migration from the previous key. If the legacy
		   value validates against the (now-broader) crypto union, move
		   it to the new key and clean up the old one. */
		const legacy = localStorage.getItem(STORAGE_KEY_CRYPTO_LEGACY);
		if (isCrypto(legacy)) {
			localStorage.setItem(STORAGE_KEY_CRYPTO, legacy);
			localStorage.removeItem(STORAGE_KEY_CRYPTO_LEGACY);
			return legacy;
		}
	} catch {
		/* see loadStablecoin */
	}
	return DEFAULT_CRYPTO;
}

let _defaultStablecoin = $state<Stablecoin>(loadStablecoin());
let _defaultCrypto = $state<DefaultCrypto>(loadCrypto());

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
	get defaultCrypto() {
		return _defaultCrypto;
	},
	setDefaultCrypto(value: DefaultCrypto) {
		_defaultCrypto = value;
		if (!browser) return;
		try {
			localStorage.setItem(STORAGE_KEY_CRYPTO, value);
		} catch {
			/* see setDefaultStablecoin */
		}
	}
};
