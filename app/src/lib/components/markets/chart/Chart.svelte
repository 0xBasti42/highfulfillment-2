<script lang="ts">
	import { setContext } from 'svelte';
	import TokenInfo from './token-info/TokenInfo.svelte';
	import ChartSettings from './chart-settings/ChartSettings.svelte';
	import ChartTools from './chart-tools/ChartTools.svelte';
	import PriceChart from './price-chart/PriceChart.svelte';
	import Indicators from './indicators/Indicators.svelte';
	import { PRICE_CHART_CTX, type PriceChartContext } from './price-chart/context';

	// Created here (rather than inside PriceChart) so the sibling ChartTools
	// palette can read the same context. PriceChart is the writer for both
	// `chart` and `drawing`; ChartTools and indicator children are readers.
	const ctx = $state<PriceChartContext>({ chart: null, drawing: null });
	setContext(PRICE_CHART_CTX, ctx);

	let timeScaleHeight = $state(26);
	let priceScaleWidth = $state(56);

	let isSettingsOpen = $state(false);
	let buttonRef: HTMLButtonElement | undefined = $state();
	let panelRef: HTMLDivElement | undefined = $state();
	let chartRef: HTMLDivElement | undefined = $state();

	let panelX = $state(0);
	let panelY = $state(0);
	let isDragging = $state(false);

	// Captured at pointerdown so subsequent moves are computed against a stable origin
	// rather than accumulating floating-point drift across frames.
	let dragOrigin = { pointerX: 0, pointerY: 0, panelX: 0, panelY: 0 };

	// Brief overlay covering the chart's mount sequence (autoSize layout pass,
	// pane setHeight rAF deferral, indicator series registration) so the user
	// doesn't see the chart settle into place. Fixed duration — no chart-readiness
	// signal so this can't drift if the mount pipeline grows new async steps.
	const CHART_LOADING_DURATION_MS = 1200;
	let isChartLoading = $state(true);

	$effect(() => {
		const timeoutId = setTimeout(() => {
			isChartLoading = false;
		}, CHART_LOADING_DURATION_MS);
		return () => clearTimeout(timeoutId);
	});

	function clamp(value: number, min: number, max: number): number {
		return Math.max(min, Math.min(value, max));
	}

	function computePanelPosition() {
		if (!buttonRef || !chartRef || !panelRef) return;
		const chartRect = chartRef.getBoundingClientRect();
		const buttonRect = buttonRef.getBoundingClientRect();
		const panelWidth = panelRef.offsetWidth;
		const panelHeight = panelRef.offsetHeight;

		// Default: right-aligned with the button's right edge, panel's bottom edge
		// at the chart's vertical midpoint (~50% from the bottom of the chart).
		const x = buttonRect.right - chartRect.left - panelWidth - priceScaleWidth;
		const y = chartRect.height / 2 - panelHeight + 120;

		panelX = clamp(x, 0, chartRect.width - panelWidth);
		panelY = clamp(y, 0, chartRect.height - panelHeight);
	}

	function toggleSettings() {
		if (isSettingsOpen) {
			isSettingsOpen = false;
			return;
		}
		// Recompute on every open so the panel resets to its anchored position
		// rather than persisting wherever it was last dragged.
		computePanelPosition();
		isSettingsOpen = true;
	}

	function closeSettings() {
		isSettingsOpen = false;
	}

	function onDragStart(event: PointerEvent) {
		if (!panelRef) return;
		isDragging = true;
		dragOrigin = {
			pointerX: event.clientX,
			pointerY: event.clientY,
			panelX,
			panelY
		};
		// Pointer capture routes all subsequent move/up events to this element,
		// so the chart canvas underneath can't steal them mid-drag.
		(event.currentTarget as HTMLElement).setPointerCapture(event.pointerId);
		event.preventDefault();
	}

	function onDragMove(event: PointerEvent) {
		if (!isDragging || !chartRef || !panelRef) return;
		const dx = event.clientX - dragOrigin.pointerX;
		const dy = event.clientY - dragOrigin.pointerY;
		const chartRect = chartRef.getBoundingClientRect();
		const panelWidth = panelRef.offsetWidth;
		const panelHeight = panelRef.offsetHeight;

		panelX = clamp(dragOrigin.panelX + dx, 0, chartRect.width - panelWidth);
		panelY = clamp(dragOrigin.panelY + dy, 0, chartRect.height - panelHeight);
	}

	function onDragEnd(event: PointerEvent) {
		if (!isDragging) return;
		isDragging = false;
		const target = event.currentTarget as HTMLElement;
		if (target.hasPointerCapture(event.pointerId)) {
			target.releasePointerCapture(event.pointerId);
		}
	}

	$effect(() => {
		if (!isSettingsOpen) return;

		function onPointerDownOutside(event: MouseEvent) {
			const target = event.target as Node | null;
			if (!target) return;
			if (panelRef?.contains(target)) return;
			if (buttonRef?.contains(target)) return;
			closeSettings();
		}

		function onKeyDown(event: KeyboardEvent) {
			if (event.key === 'Escape') closeSettings();
		}

		document.addEventListener('mousedown', onPointerDownOutside);
		document.addEventListener('keydown', onKeyDown);

		return () => {
			document.removeEventListener('mousedown', onPointerDownOutside);
			document.removeEventListener('keydown', onKeyDown);
		};
	});
</script>

<div class="chart" bind:this={chartRef}>
	<TokenInfo />
	<ChartSettings />
	<div class="chart-container">
		<ChartTools />
		<div class="price-chart-container">
			<div class="price-chart-slot">
				<PriceChart bind:timeScaleHeight bind:priceScaleWidth>
					<Indicators />
				</PriceChart>
				<button
					type="button"
					class="settings-button"
					aria-label="Chart settings"
					aria-expanded={isSettingsOpen}
					aria-controls="chart-settings-panel"
					style="width: calc({priceScaleWidth}px + 1px); height: calc({timeScaleHeight}px + 1px);"
					bind:this={buttonRef}
					onclick={toggleSettings}
				>
					<img src="/icons/settings.svg" alt="Chart settings" class="settings-button-icon" />
				</button>
			</div>
		</div>
	</div>

	<div
		class="chart-loading"
		class:chart-loading--visible={isChartLoading}
		role="status"
		aria-label="Loading chart"
		aria-hidden={!isChartLoading}
	>
		<div class="chart-loading__spinner"></div>
	</div>

	<div
		id="chart-settings-panel"
		class="settings-panel"
		class:settings-panel--open={isSettingsOpen}
		class:settings-panel--dragging={isDragging}
		role="dialog"
		aria-label="Chart settings"
		aria-hidden={!isSettingsOpen}
		style="left: {panelX}px; top: {panelY}px;"
		bind:this={panelRef}
	>
		<div
			class="settings-panel__drag-handle"
			role="presentation"
			onpointerdown={onDragStart}
			onpointermove={onDragMove}
			onpointerup={onDragEnd}
			onpointercancel={onDragEnd}
		>
			<span class="settings-panel__grip"></span>
		</div>

		<section class="settings-panel__section">
			<p class="settings-panel__label">Chart Type</p>
			<div class="settings-panel__segments">
				<button type="button" class="segment segment--active">Candles</button>
				<button type="button" class="segment">Line</button>
				<button type="button" class="segment">Area</button>
			</div>
		</section>

		<section class="settings-panel__section">
			<p class="settings-panel__label">Display</p>
			<label class="toggle-row">
				<span>Grid</span>
				<input type="checkbox" checked={true} />
			</label>
			<label class="toggle-row">
				<span>Crosshair</span>
				<input type="checkbox" checked={true} />
			</label>
			<label class="toggle-row">
				<span>Watermark</span>
				<input type="checkbox" checked={false} />
			</label>
		</section>

		<section class="settings-panel__section">
			<p class="settings-panel__label">Price</p>
			<div class="settings-panel__segments">
				<button type="button" class="segment">Left</button>
				<button type="button" class="segment segment--active">Right</button>
			</div>
		</section>

		<section class="settings-panel__section">
			<p class="settings-panel__label">Scale</p>
			<label class="toggle-row">
				<span>Regular</span>
				<input type="checkbox" checked={false}/>
			</label>
			<label class="toggle-row">
				<span>Inverted</span>
				<input type="checkbox" checked={false}/>
			</label>
			<label class="toggle-row">
				<span>Percentage</span>
				<input type="checkbox" checked={false}/>
			</label>
			<label class="toggle-row">
				<span>Logarithmic</span>
				<input type="checkbox" checked={true}/>
			</label>
		</section>

		<section class="settings-panel__section">
			<div class="settings-panel__segments">
				<button type="button" class="segment">
					More settings
					<span class="more-settings-icon"><i class="fa-solid fa-chevron-right"></i></span>
				</button>
			</div>
		</section>
	</div>
</div>

<style>
	.chart {
		position: relative;
		border-bottom: 1px solid var(--color-border);
		height: auto;
		width: 100%;
		display: flex;
		flex-direction: column;
		align-items: stretch;
		justify-content: flex-start;
	}

	.chart-container {
		display: flex;
		flex-direction: row;
		align-items: stretch;
		justify-content: flex-start;
		width: 100%;
	}

	.price-chart-container {
		flex: 1;
		min-width: 0;
		display: flex;
		flex-direction: column;
		align-items: stretch;
		justify-content: flex-start;
	}

	.price-chart-slot {
		position: relative;
		display: flex;
		flex-direction: column;
		align-items: stretch;
		justify-content: flex-start;
	}

	.settings-button {
		position: absolute;
		bottom: 0;
		right: 0;
		z-index: 3;
		min-width: 0;
		padding: 0;
		display: flex;
		align-items: center;
		justify-content: center;
		background: var(--color-surface-elevated);
		border-top: 1px solid transparent;
		border-left: 1px solid transparent;
		border-radius: 0;
		color: var(--color-text-muted);
		font-size: var(--text-sm);
		cursor: pointer;
		transition: all var(--transition-base);
	}

	.settings-button:hover {
		color: var(--color-text);
		background-color: var(--color-surface-muted);
		border-top: 1px solid transparent;
		border-left: 1px solid transparent;
	}

	.settings-button:active {
		opacity: 0.8;
	}

	.settings-button-icon {
		width: 18px;
		height: 18px;
		opacity: 0.5;
		transition: opacity var(--transition-base);
	}

	.settings-button[aria-expanded='true'] .settings-button-icon {
		opacity: 1;
	}

	.settings-panel {
		position: absolute;
		z-index: 4;
		width: 280px;
		max-height: 540px;
		overflow-y: auto;
		padding: var(--space-md);
		background-color: var(--color-surface-muted);
		border: 1px solid var(--color-border-light);
		border-radius: var(--radius-sm);
		box-shadow: 0 8px 24px rgba(0, 0, 0, 0.4);
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
		visibility: hidden;
		pointer-events: none;
		opacity: 0;
		transition: opacity var(--transition-fast);
	}

	.settings-panel--open {
		visibility: visible;
		pointer-events: auto;
		opacity: 1;
	}

	.settings-panel--dragging {
		user-select: none;
		transition: none;
	}

	.settings-panel__drag-handle {
		display: flex;
		align-items: center;
		justify-content: center;
		height: 14px;
		margin: calc(var(--space-sm) * -1) 0 var(--space-xs);
		cursor: grab;
		touch-action: none;
	}

	.settings-panel--dragging .settings-panel__drag-handle {
		cursor: grabbing;
	}

	.settings-panel__grip {
		display: block;
		width: 36px;
		height: 4px;
		background-color: var(--color-border-strong);
		border-radius: 2px;
		transition: background-color var(--transition-base);
	}

	.settings-panel__drag-handle:hover .settings-panel__grip,
	.settings-panel--dragging .settings-panel__grip {
		background-color: var(--color-text-muted);
	}

	.settings-panel__section {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}

	.settings-panel__label {
		margin: 0;
		color: var(--color-text-muted);
		font-size: var(--text-xs);
		letter-spacing: var(--tracking-default);
	}

	.settings-panel__segments {
		display: flex;
		gap: var(--space-xs);
	}

	.segment {
		all: unset;
		flex: 1;
		min-width: 0;
		padding: var(--space-xs) var(--space-sm);
		text-align: center;
		color: var(--color-text-muted);
		font-size: var(--text-sm);
		background-color: var(--color-surface-muted);
		border: 1px solid var(--color-surface-elevated);
		border-radius: var(--radius-sm);
		cursor: pointer;
		transition:
			color var(--transition-base),
			background var(--transition-base);

		display: flex;
		align-items: center;
		justify-content: space-between;
	}

	.segment:hover {
		color: var(--color-text);
		background-color: var(--color-surface-elevated);
	}

	.segment--active {
		color: var(--color-text);
		background: var(--color-surface-elevated);
	}

	.more-settings-icon {
		display: flex;
		align-items: center;
		justify-content: flex-end;
		font-size: 10px;
	}

	.toggle-row {
		display: flex;
		align-items: center;
		justify-content: space-between;
		color: var(--color-text);
		font-size: var(--text-sm);
		cursor: pointer;
	}

	.chart-loading {
		position: absolute;
		inset: 0;
		z-index: 5;
		display: flex;
		align-items: center;
		justify-content: center;
		background-color: var(--color-surface-elevated);
		visibility: hidden;
		pointer-events: none;
		opacity: 0;
		/* Delay the visibility flip until the opacity fade-out finishes —
		   without this, the element jumps to hidden before the fade plays. */
		transition:
			opacity var(--transition-slow),
			visibility 0s linear var(--transition-slow);
	}

	.chart-loading--visible {
		visibility: visible;
		pointer-events: auto;
		opacity: 1;
		/* On fade-in, visibility flips immediately so the element is visible
		   while opacity transitions from 0 to 1. */
		transition: opacity var(--transition-slow);
	}

	.chart-loading__spinner {
		width: 32px;
		height: 32px;
		border: 2px solid var(--color-surface-muted);
		border-top-color: var(--color-text);
		border-radius: 50%;
		animation: chart-loading-spin 0.8s linear infinite;
	}

	@keyframes chart-loading-spin {
		to {
			transform: rotate(360deg);
		}
	}
</style>
