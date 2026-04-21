<script lang="ts">
	const timeframes = [
		{ label: '5m', value: '5m' },
		{ label: '15m', value: '15m' },
		{ label: '1H', value: '1H' },
		{ label: '12H', value: '12H' }
	];

	let selectedTimeframe = $state('15m');
</script>

<div class="chart-settings">
	<div class="timeframe-container">
		{#each timeframes as timeframe}
			<button
				type="button"
				class="timeframe"
				class:timeframe--active={timeframe.value === selectedTimeframe}
				onclick={() => (selectedTimeframe = timeframe.value)}
			>
				<p>{timeframe.label}</p>
			</button>
		{/each}
		<div class="more-timeframes">
			<i class="fa-solid fa-chevron-down"></i>
		</div>
	</div>

	<div class="chart-type-container">
		<img src="/icons/candles.svg" alt="Candlestick chart" class="chart-type-icon" />
	</div>

	<div class="indicator-container">
		<p>ƒ×</p>
		<p>Indicators</p>
	</div>
</div>

<style>
	.chart-settings {
		height: 50px;
		width: 100%;
		background-color: var(--color-surface-muted);
		display: flex;
		align-items: center;
		justify-content: flex-start;
	}

	.timeframe-container,
	.chart-type-container,
	.indicator-container {
		height: 60%;
		display: flex;
		align-items: center;
		border-right: 1px solid var(--color-border);
	}

	.timeframe-container {
		justify-content: flex-start;
		gap: 20px;
		padding: 0 20px;
	}

	.chart-type-container {
		justify-content: center;
		padding: 0 10px;
	}

	.indicator-container {
		justify-content: center;
		gap: 8px;
		padding: 0 20px;
	}

	.timeframe {
		all: unset;
		box-sizing: border-box;
		display: flex;
		align-items: center;
		justify-content: center;
		padding: 0 5px;
		cursor: pointer;
		transition: all var(--transition-base);
	}

	.timeframe p {
		color: var(--color-text-muted);
	}

	.timeframe--active p {
		color: #d6d6d6;
	}

	.timeframe:hover:not(.timeframe--active) p {
		color: var(--color-text);
	}

	.more-timeframes {
		display: flex;
		align-items: center;
		justify-content: center;
		margin-left: 0;
		cursor: pointer;
	}

	.more-timeframes i {
		margin-bottom: 2px;
		font-size: 12px;
		color: #565656;
		transition: all var(--transition-base);
	}

	.more-timeframes:hover i {
		color: var(--color-text-muted);
		transform: rotate(180deg);
	}

	.more-timeframes:active i {
		opacity: 0.7;
	}

	.chart-type-icon {
		width: 20px;
		height: 20px;
	}

	.indicator-container p:first-child {
		font-size: 18px;
		color: var(--color-text-muted);
	}
</style>
