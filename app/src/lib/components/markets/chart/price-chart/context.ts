import type { IChartApi } from 'lightweight-charts';
import type { ChartDrawingAdapter } from '../drawing/drawing.adapter.svelte';

/**
 * Svelte context key + shape for the chart subtree.
 *
 * The value is a reactive `$state` object so consumers can `$effect` against
 * its fields and re-run when they're created or destroyed.
 *
 * - `chart`: the lightweight-charts instance. Indicator components read this
 *   to register themselves as panes via `chart.addSeries(..., paneIndex)`.
 *
 * - `drawing`: a thin facade over `lightweight-charts-drawing`'s `DrawingManager`,
 *   exposed so the sibling `ChartTools` palette can activate tools, delete
 *   selected drawings, etc. Wrapped in an adapter so swapping the underlying
 *   drawing library later is a one-file change.
 *
 * The context is created and `setContext`-ed in `Chart.svelte` (the common
 * parent of `PriceChart` and `ChartTools`) so siblings can share state.
 * `PriceChart.svelte` is the writer for both fields; everything else reads.
 */

export const PRICE_CHART_CTX = Symbol('priceChart');

export interface PriceChartContext {
	chart: IChartApi | null;
	drawing: ChartDrawingAdapter | null;
}
