import type { IChartApi } from 'lightweight-charts';

/**
 * Svelte context key + shape for sharing a lightweight-charts instance from
 * `PriceChart.svelte` down to indicator components nested inside it.
 *
 * The value is a reactive `$state` object so consumers can `$effect` against
 * `ctx.chart` and re-run when the chart is created or destroyed. Indicator
 * components register themselves as panes by calling `chart.addSeries(..., paneIndex)`
 * once the chart is available.
 */

export const PRICE_CHART_CTX = Symbol('priceChart');

export interface PriceChartContext {
	chart: IChartApi | null;
}
