import type { HistogramData, UTCTimestamp } from 'lightweight-charts';
import { createPrng } from '$lib/utils/seededRandom';

// Seed differs from the candle data so the volume profile doesn't look like
// an obvious mathematical derivative of the price series.

const BAR_COUNT = 180;
const HOUR_SECONDS = 60 * 60;

const UP_COLOR = '#19817680';
const DOWN_COLOR = '#AE323E80';

function generateVolumeBars(): HistogramData<UTCTimestamp>[] {
	const rand = createPrng(0xbeef_cafe);

	// Time anchor matches the candle data: the latest bar lands on the most recent
	// whole hour so the indicator visually aligns with the price chart's x range.
	const nowSeconds = Math.floor(Date.now() / 1000);
	const latestHour = nowSeconds - (nowSeconds % HOUR_SECONDS);
	const firstHour = latestHour - (BAR_COUNT - 1) * HOUR_SECONDS;

	const bars: HistogramData<UTCTimestamp>[] = [];

	let baseline = 5_000;
	const meanBaseline = 5_000;
	const meanReversion = 0.05;

	for (let i = 0; i < BAR_COUNT; i++) {
		const time = (firstHour + i * HOUR_SECONDS) as UTCTimestamp;

		// Random walk on baseline so volume has clusters of high/low activity
		// rather than looking like uniform noise across the series.
		baseline += (meanBaseline - baseline) * meanReversion + (rand() - 0.5) * 1_500;
		const value = Math.max(500, Math.round(baseline + (rand() - 0.5) * 4_000));

		// Coarse coin-flip on direction. In production this would be derived from
		// whether the matching candle closed above or below its open.
		const color = rand() > 0.48 ? UP_COLOR : DOWN_COLOR;

		bars.push({ time, value, color });
	}

	return bars;
}

export const mockVolumeData: HistogramData<UTCTimestamp>[] = generateVolumeBars();
