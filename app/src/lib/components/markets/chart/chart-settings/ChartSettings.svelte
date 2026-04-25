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

	<div class="division">
		<p>mock</p>
	</div>

	<div class="indicator-container">
		<p>ƒ×</p>
		<p>Indicators</p>
	</div>

	<div class="division">
		<p>mock</p>
	</div>

	<div class="chart-settings-right">
		<img src="/brand/logo.svg" alt="Watermark" class="chart-settings-right-icon" />
	</div>
</div>

<style>
	.chart-settings {
		height: 50px;
		width: 100%;
		background-color: var(--color-surface-elevated);
		display: flex;
		align-items: center;
		justify-content: flex-start;
		border-bottom: 1px solid var(--color-border-light);
	}

	.timeframe-container,
	.indicator-container {
		height: 50%;
		display: flex;
		align-items: center;
	}

	.timeframe-container {
		justify-content: flex-start;
		gap: 20px;
		padding: 0 20px;
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
		transition: all var(--transition-base);
	}

	.more-timeframes i {
		display: block;
		font-size: 12px;
		line-height: 1;
		color: var(--color-text-faded);
		cursor: default;
		transition:
			color var(--transition-base),
			transform var(--transition-base);
		padding: 3px;
	}

	.more-timeframes:hover i {
		transform: rotate(180deg);
	}

	.indicator-container {
		cursor: pointer;
		transition: all var(--transition-base);
		height: 60%;
		border-right: 0;
	}

	.indicator-container:hover {
		color: var(--color-text);
		background-color: var(--color-surface-muted);
	}

	.indicator-container:active {
		opacity: 0.8;
	}

	.indicator-container p:first-child {
		font-size: 16px;
		color: var(--color-text-muted);
	}

	.division {
		height: 60%;
		width: 1px;
		background-color: var(--color-border);
	}

	.division p {
		opacity: 0;
	}

	.chart-settings-right {
		flex: 1;
		display: flex;
		align-items: center;
		justify-content: flex-end;
		padding: 0 20px;
		opacity: 0.3;
	}

	.chart-settings-right-icon {
		width: 100px;
		filter: grayscale(100%);
		opacity: 1;
	}
</style>
