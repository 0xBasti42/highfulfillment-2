<script lang="ts">
	import { onMount, setContext, type Snippet } from 'svelte';
	import {
		CandlestickSeries,
		CrosshairMode,
		createChart,
		type IChartApi,
		type ISeriesApi
	} from 'lightweight-charts';
	import { mockCandleData } from './mockData';
	import { PRICE_CHART_CTX, type PriceChartContext } from './context';

	interface Props {
		timeScaleHeight?: number;
		priceScaleWidth?: number;
		children?: Snippet;
	}

	let {
		timeScaleHeight = $bindable(26),
		priceScaleWidth = $bindable(56),
		children
	}: Props = $props();

	let container: HTMLDivElement;

	// Reactive context object: indicator children read `ctx.chart` inside an
	// $effect, so flipping this from null → IChartApi (on mount) and back
	// (on teardown) drives their pane registration / cleanup.
	const ctx = $state<PriceChartContext>({ chart: null });
	setContext(PRICE_CHART_CTX, ctx);

	onMount(() => {
		const chart: IChartApi = createChart(container, {
			autoSize: true,
			layout: {
				background: { color: 'transparent' },
				textColor: '#999999',
				fontFamily: 'Inter, system-ui, sans-serif',
				fontSize: 11,
				panes: {
					separatorColor: '#303030',
					separatorHoverColor: '#404040'
				}
			},
			grid: {
				vertLines: { color: 'rgba(48, 48, 48, 0.4)' },
				horzLines: { color: 'rgba(48, 48, 48, 0.4)' }
			},
			crosshair: {
				mode: CrosshairMode.Normal,
				vertLine: { color: '#404040', width: 1, style: 3, labelBackgroundColor: '#404040' },
				horzLine: { color: '#404040', width: 1, style: 3, labelBackgroundColor: '#404040' }
			},
			rightPriceScale: {
				borderColor: '#303030',
				scaleMargins: { top: 0.1, bottom: 0.08 }
			},
			timeScale: {
				borderColor: '#303030',
				timeVisible: true,
				secondsVisible: false
			}
		});

		const series: ISeriesApi<'Candlestick'> = chart.addSeries(CandlestickSeries, {
			upColor: '#198176',
			downColor: '#AE323E',
			borderUpColor: '#198176',
			borderDownColor: '#AE323E',
			wickUpColor: '#198176',
			wickDownColor: '#AE323E',
			priceFormat: { type: 'price', precision: 4, minMove: 0.0001 }
		});

		series.setData(mockCandleData);
		chart.timeScale().fitContent();

		// Publish the chart instance so child indicator components can register
		// themselves as panes via `chart.addSeries(..., paneIndex)`.
		ctx.chart = chart;

		// Exposes live axis dimensions so the parent can align chrome (e.g. the
		// settings button) flush with where the time and price axes meet.
		// Guard against non-positive reads: lightweight-charts can return 0 before
		// its first paint, which would otherwise collapse any consumer sized by these.
		const syncAxisDims = () => {
			const h = chart.timeScale().height();
			const w = chart.priceScale('right').width();
			if (h > 0) timeScaleHeight = h;
			if (w > 0) priceScaleWidth = w;
		};

		syncAxisDims();
		requestAnimationFrame(syncAxisDims);
		chart.timeScale().subscribeSizeChange(syncAxisDims);
		chart.timeScale().subscribeVisibleTimeRangeChange(syncAxisDims);

		return () => {
			// Null first so any indicator effects observing `ctx.chart` stop trying
			// to call into a chart that's about to be torn down.
			ctx.chart = null;
			chart.remove();
		};
	});
</script>

<div class="price-chart">
	<div class="price-chart__canvas" bind:this={container}></div>
	{@render children?.()}
</div>

<style>
	.price-chart {
		position: relative;
		overflow: hidden;
		background-color: var(--color-surface-elevated);
		display: flex;
		flex-direction: column;
		align-items: stretch;
		justify-content: flex-start;
		width: 100%;
		min-height: 625px;
	}

	.price-chart::before {
		content: '';
		position: absolute;
		inset: 0;
		background-image: url('/brand/logo.svg');
		background-repeat: no-repeat;
		background-position: calc(50% - 60px) calc(50% - 50px);
		background-size: 20% auto;
		filter: grayscale(0.1);
		opacity: 0.08;
		pointer-events: none;
		z-index: 0;
	}

	.price-chart__canvas {
		position: relative;
		z-index: 1;
		flex: 1;
		width: 100%;
		min-height: 0;
	}
</style>
