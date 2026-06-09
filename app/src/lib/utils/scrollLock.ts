/**
 * Shared scroll-lock counter for full-screen overlays (modals,
 * sidebars). Each overlay acquires a lock when it opens and releases
 * it when it closes; the body `overflow-y` is set to `hidden` only
 * while at least one lock is held, and restored when the last lock
 * is released.
 *
 * Why a counter instead of a boolean: lets multiple overlays stack
 * (e.g. main Sidebar open + AccountSidebar opens via deep-link)
 * without one closing accidentally releasing another's lock. The
 * mutation to body.style is gated on the 0↔1 boundary so we never
 * pay the cost of re-setting a style that's already correct.
 *
 * Why `overflow-y` (vs. `overflow`): horizontal overflow is rarely
 * a concern here, and toggling only the y-axis avoids clobbering any
 * future horizontal-scroll behaviour an upstream rule might add.
 *
 * Usage pattern in a consumer:
 *
 *   $effect(() => {
 *     if (isOpen) {
 *       scrollLock.acquire();
 *       return () => scrollLock.release();
 *     }
 *   });
 *
 * The cleanup-return form means component unmount and condition flip
 * both release automatically — no manual bookkeeping.
 */

import { browser } from '$app/environment';

let count = 0;

export const scrollLock = {
	acquire() {
		count += 1;
		if (browser && count === 1) {
			document.body.style.overflowY = 'hidden';
		}
	},
	release() {
		count = Math.max(0, count - 1);
		if (browser && count === 0) {
			document.body.style.overflowY = '';
		}
	}
};
