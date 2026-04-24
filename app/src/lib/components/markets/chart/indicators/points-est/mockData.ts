import type { LineData, UTCTimestamp } from 'lightweight-charts';
import { createPrng } from '$lib/utils/seededRandom';

const POINT_COUNT = 180;
const HOUR_SECONDS = 60 * 60;

function timeAxis(): UTCTimestamp[] {
	const nowSeconds = Math.floor(Date.now() / 1000);
	const latestHour = nowSeconds - (nowSeconds % HOUR_SECONDS);
	const firstHour = latestHour - (POINT_COUNT - 1) * HOUR_SECONDS;
	return Array.from({ length: POINT_COUNT }, (_, i) => (firstHour + i * HOUR_SECONDS) as UTCTimestamp);
}

function generateLine(
	seed: number,
	options: { mean: number; meanReversion: number; volatility: number; startValue?: number }
): LineData<UTCTimestamp>[] {
	const rand = createPrng(seed);
	const times = timeAxis();
	let value = options.startValue ?? options.mean;

	return times.map((time) => {
		const drift = (options.mean - value) * options.meanReversion;
		const shock = (rand() - 0.5) * 2 * options.volatility;
		value = Math.max(0, value + drift + shock);

		return { time, value: Math.round(value * 10) / 10 };
	});
}

// Actual matchweek points: noisier, faster to revert, higher volatility.
// This is the "live" series the user is mainly tracking.
export const mockPointsData: LineData<UTCTimestamp>[] = generateLine(0xface_b00c, {
	mean: 50,
	meanReversion: 0.04,
	volatility: 2.5
});

// Estimated points baseline: smoother, slower-moving curve. Reads as the
// "expected" line that the actual points oscillate around.
export const mockEstData: LineData<UTCTimestamp>[] = generateLine(0xa11_c0de, {
	mean: 50,
	meanReversion: 0.12,
	volatility: 0.8,
	startValue: 48
});
