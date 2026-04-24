<script lang="ts">
	import { getContext } from 'svelte';
	import { LineSeries, type ISeriesApi } from 'lightweight-charts';
	import { mockPointsData, mockEstData } from './mockData';
	import { PRICE_CHART_CTX, type PriceChartContext } from '../../price-chart/context';

	interface Props {
		defaultHeight?: number;
	}

	let { defaultHeight = 50 }: Props = $props();

	const ctx = getContext<PriceChartContext>(PRICE_CHART_CTX);

	$effect(() => {
		const chart = ctx.chart;
		if (!chart) return;

		const paneIndex = chart.panes().length;

		const sharedOptions = {
			lineWidth: 1,
			priceFormat: { type: 'price', precision: 1, minMove: 0.1 }
		} as const;

		// EST baseline added first so the actual Points line paints on top of it.
		const estSeries: ISeriesApi<'Line'> = chart.addSeries(
			LineSeries,
			{ ...sharedOptions, color: '#198176' },
			paneIndex
		);
		estSeries.setData(mockEstData);

		const pointsSeries: ISeriesApi<'Line'> = chart.addSeries(
			LineSeries,
			{ ...sharedOptions, color: '#666666' },
			paneIndex
		);
		pointsSeries.setData(mockPointsData);

		// Defer setHeight to the next frame so the chart's autoSize ResizeObserver
		// has had time to fire and the chart knows its real container dimensions.
		// Calling setHeight against an unsized chart computes a stretch factor of
		// (height / 0) which collapses to a tiny default once the chart finally sizes.
		const rafId = requestAnimationFrame(() => {
			chart.panes()[paneIndex]?.setHeight(defaultHeight);
		});

		return () => {
			cancelAnimationFrame(rafId);
			try {
				chart.removeSeries(pointsSeries);
				chart.removeSeries(estSeries);
			} catch {
				/* chart already destroyed */
			}
		};
	});
</script>
