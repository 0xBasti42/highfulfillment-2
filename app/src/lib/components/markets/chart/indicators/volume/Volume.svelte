<script lang="ts">
	import { getContext } from 'svelte';
	import { HistogramSeries, type IPaneApi, type ISeriesApi, type Time } from 'lightweight-charts';
	import { mockVolumeData } from './mockData';
	import { PRICE_CHART_CTX, type PriceChartContext } from '../../price-chart/context';

	interface Props {
		defaultHeight?: number;
	}

	let { defaultHeight = 30 }: Props = $props();

	const ctx = getContext<PriceChartContext>(PRICE_CHART_CTX);

	let pane = $state<IPaneApi<Time> | null>(null);

	// Effect 1 — register the pane and series. Only depends on `ctx.chart`,
	// so prop changes don't tear down the pane (see PointsEst.svelte for the
	// full reasoning behind splitting registration from height application).
	$effect(() => {
		const chart = ctx.chart;
		if (!chart) return;

		// Auto-assign to the next available pane index based on current pane count.
		// Indicator components mount in source order, so PointsEst (mounted first)
		// gets pane 1 and Volume (mounted second) gets pane 2.
		const paneIndex = chart.panes().length;

		const series: ISeriesApi<'Histogram'> = chart.addSeries(
			HistogramSeries,
			{
				color: '#198176',
				priceFormat: { type: 'volume' }
			},
			paneIndex
		);

		series.setData(mockVolumeData);

		pane = chart.panes()[paneIndex] ?? null;

		return () => {
			pane = null;
			// Chart may already be torn down by the time this cleanup runs (e.g.
			// PriceChart unmounting first). Swallow the error in that case.
			try {
				chart.removeSeries(series);
			} catch {
				/* chart already destroyed */
			}
		};
	});

	// Effect 2 — apply the pane height. Synchronous reads of both `pane` and
	// `defaultHeight` so Svelte tracks them as dependencies; reads inside the
	// rAF callback alone would NOT establish dependencies.
	$effect(() => {
		const p = pane;
		const height = defaultHeight;
		if (!p) return;

		const rafId = requestAnimationFrame(() => {
			p.setHeight(height);
		});
		return () => cancelAnimationFrame(rafId);
	});
</script>
