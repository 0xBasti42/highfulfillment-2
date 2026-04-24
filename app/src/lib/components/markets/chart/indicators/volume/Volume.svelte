<script lang="ts">
	import { getContext } from 'svelte';
	import { HistogramSeries, type ISeriesApi } from 'lightweight-charts';
	import { mockVolumeData } from './mockData';
	import { PRICE_CHART_CTX, type PriceChartContext } from '../../price-chart/context';

	interface Props {
		defaultHeight?: number;
	}

	let { defaultHeight = 30 }: Props = $props();

	const ctx = getContext<PriceChartContext>(PRICE_CHART_CTX);

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

		// Defer setHeight to the next frame — see PointsEst.svelte for the reasoning;
		// short version: setHeight is stretch-factor-based and produces a collapsed
		// pane if called before the chart has had its initial autoSize layout pass.
		const rafId = requestAnimationFrame(() => {
			chart.panes()[paneIndex]?.setHeight(defaultHeight);
		});

		return () => {
			cancelAnimationFrame(rafId);
			// Chart may already be torn down by the time this cleanup runs (e.g.
			// PriceChart unmounting first). Swallow the error in that case.
			try {
				chart.removeSeries(series);
			} catch {
				/* chart already destroyed */
			}
		};
	});
</script>
