<script lang="ts">
	import { getContext } from 'svelte';
	import { LineSeries, type IPaneApi, type ISeriesApi, type Time } from 'lightweight-charts';
	import { mockPointsData, mockEstData } from './mockData';
	import { PRICE_CHART_CTX, type PriceChartContext } from '../../price-chart/context';

	interface Props {
		defaultHeight?: number;
	}

	let { defaultHeight = 50 }: Props = $props();

	const ctx = getContext<PriceChartContext>(PRICE_CHART_CTX);

	// Reactive pane reference so the height-applying effect below can react to
	// the pane being created/torn down without depending on the chart instance
	// directly (which would conflate registration with height application).
	let pane = $state<IPaneApi<Time> | null>(null);

	// Effect 1 — register the pane and series when the chart becomes available.
	// Only depends on `ctx.chart`, so it runs once per mount and survives
	// `defaultHeight` prop changes without tearing down the series.
	$effect(() => {
		const chart = ctx.chart;
		if (!chart) return;

		const paneIndex = chart.panes().length;

		const sharedOptions = {
			lineWidth: 2,
			priceFormat: { type: 'price', precision: 1, minMove: 0.1 }
		} as const;

		// EST baseline added first so the actual Points line paints on top of it.
		const estSeries: ISeriesApi<'Line'> = chart.addSeries(
			LineSeries,
			{ ...sharedOptions, color: '#d6d6d670' },
			paneIndex
		);
		estSeries.setData(mockEstData);

		const pointsSeries: ISeriesApi<'Line'> = chart.addSeries(
			LineSeries,
			{ ...sharedOptions, color: '#99999950' },
			paneIndex
		);
		pointsSeries.setData(mockPointsData);

		pane = chart.panes()[paneIndex] ?? null;

		return () => {
			pane = null;
			try {
				chart.removeSeries(pointsSeries);
				chart.removeSeries(estSeries);
			} catch {
				/* chart already destroyed */
			}
		};
	});

	// Effect 2 — apply the pane height.
	// Reads `pane`, `defaultHeight`, and `ctx.chart` synchronously so all three
	// are tracked as dependencies. The effect re-runs whenever any change.
	//
	// Two paths depending on chart readiness:
	//   - Chart already laid out (prop change after mount): call setHeight
	//     directly. rAF here would introduce a timing window where lightweight-
	//     charts may collapse the call.
	//   - Chart not yet laid out (initial mount): defer to next frame, by which
	//     time the chart's autoSize ResizeObserver has fired and dimensions
	//     exist. setHeight against an unsized chart computes a stretch factor
	//     against zero and silently no-ops.
	$effect(() => {
		const p = pane;
		const height = defaultHeight;
		const chart = ctx.chart;
		if (!p || !chart) return;

		if (chart.timeScale().height() > 0) {
			p.setHeight(height);
			return;
		}

		const rafId = requestAnimationFrame(() => {
			p.setHeight(height);
		});
		return () => cancelAnimationFrame(rafId);
	});
</script>
