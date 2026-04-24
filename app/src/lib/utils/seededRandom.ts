/**
 * Mulberry32 seeded PRNG.
 *
 * Returns a function producing deterministic pseudo-random numbers in [0, 1)
 * for a given seed. Useful for mock data that needs to look the same on every
 * page load so visual iteration on charts, layouts, etc. isn't a moving target.
 *
 * Not cryptographically secure. Do NOT use this for anything security-sensitive.
 */
export function createPrng(seed: number): () => number {
	let state = seed >>> 0;
	return () => {
		state = (state + 0x6d2b79f5) >>> 0;
		let t = state;
		t = Math.imul(t ^ (t >>> 15), t | 1);
		t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
		return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
	};
}
