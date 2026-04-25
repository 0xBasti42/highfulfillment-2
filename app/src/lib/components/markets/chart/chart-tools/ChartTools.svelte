<script lang="ts">
	import { getContext } from 'svelte';
	import { PRICE_CHART_CTX, type PriceChartContext } from '../price-chart/context';
	import { CHART_TOOL_GROUPS } from '../drawing/tools.config';

	// Adapter is published by PriceChart on mount, so it'll be `null` for the
	// first render. Buttons are disabled until it shows up.
	const ctx = getContext<PriceChartContext>(PRICE_CHART_CTX);

	function onToolClick(toolType: string) {
		ctx.drawing?.toggleActiveTool(toolType);
	}

	function onDeleteClick() {
		ctx.drawing?.removeSelected();
	}

	function onClearClick() {
		ctx.drawing?.clearAll();
	}
</script>

<div class="chart-tools" role="toolbar" aria-label="Chart drawing tools">
	{#each CHART_TOOL_GROUPS as group, groupIndex (group.id)}
		{#if groupIndex > 0}
			<div class="chart-tools__divider" role="presentation"></div>
		{/if}
		{#each group.tools as tool (tool.type)}
			<button
				type="button"
				class="tool-btn"
				class:tool-btn--active={ctx.drawing?.state.activeTool === tool.type}
				disabled={!ctx.drawing}
				aria-label={tool.label}
				aria-pressed={ctx.drawing?.state.activeTool === tool.type}
				title={tool.label}
				onclick={() => onToolClick(tool.type)}
			>
				<svg
					class="tool-btn__icon"
					viewBox="0 0 16 16"
					fill="none"
					stroke="currentColor"
					stroke-width="1.25"
					stroke-linecap="round"
					stroke-linejoin="round"
					aria-hidden="true"
				>
					<path d={tool.icon} />
				</svg>
			</button>
		{/each}
	{/each}

	<div class="chart-tools__spacer"></div>

	<button
		type="button"
		class="tool-btn tool-btn--danger"
		disabled={!ctx.drawing?.state.hasSelection}
		aria-label="Remove selected drawing"
		title="Remove selected"
		onclick={onDeleteClick}
	>
		<svg
			class="tool-btn__icon"
			viewBox="0 0 16 16"
			fill="none"
			stroke="currentColor"
			stroke-width="1.25"
			stroke-linecap="round"
			stroke-linejoin="round"
			aria-hidden="true"
		>
			<path d="M3 4.5 L13 4.5 M5.5 4.5 L5.5 3 L10.5 3 L10.5 4.5 M4.5 4.5 L5 13.5 L11 13.5 L11.5 4.5 M6.5 6.5 L6.5 11.5 M9.5 6.5 L9.5 11.5" />
		</svg>
	</button>

	<button
		type="button"
		class="tool-btn tool-btn--danger"
		disabled={!ctx.drawing}
		aria-label="Clear all drawings"
		title="Clear all"
		onclick={onClearClick}
	>
		<svg
			class="tool-btn__icon"
			viewBox="0 0 16 16"
			fill="none"
			stroke="currentColor"
			stroke-width="1.25"
			stroke-linecap="round"
			stroke-linejoin="round"
			aria-hidden="true"
		>
			<path d="M2.5 13.5 L13.5 2.5 M2.5 2.5 L13.5 13.5" />
		</svg>
	</button>
</div>

<style>
	.chart-tools {
		flex-shrink: 0;
		width: 60px;
		background-color: var(--color-surface-elevated);
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: flex-start;
		gap: var(--space-xs);
		padding: var(--space-sm) 0;
		border-right: 1px solid var(--color-border-light);
	}

	.chart-tools__divider {
		width: 28px;
		height: 1px;
		margin: var(--space-xs) 0;
		background-color: var(--color-border-light);
	}

	/* Pushes the destructive controls to the bottom of the column, keeping
	   creation and deletion visually separated even as the tool list grows. */
	.chart-tools__spacer {
		flex: 1;
		min-height: var(--space-sm);
	}

	.tool-btn {
		all: unset;
		box-sizing: border-box;
		width: 32px;
		height: 32px;
		display: flex;
		align-items: center;
		justify-content: center;
		color: var(--color-text-muted);
		border-radius: var(--radius-sm);
		cursor: pointer;
		transition:
			color var(--transition-base),
			background-color var(--transition-base);
	}

	.tool-btn:hover:not(:disabled) {
		color: var(--color-text);
		background-color: var(--color-surface-muted);
	}

	.tool-btn:active:not(:disabled) {
		opacity: 0.8;
	}

	.tool-btn:disabled {
		cursor: not-allowed;
		opacity: 0.35;
	}

	.tool-btn--active {
		color: var(--color-text);
		background-color: var(--color-surface-muted);
	}

	/* Hover-only red tint so the destructive intent is obvious only when the
	   user is committing to the click — keeps the idle palette visually calm. */
	.tool-btn--danger:hover:not(:disabled) {
		color: var(--color-negative, #ae323e);
	}

	.tool-btn__icon {
		width: 18px;
		height: 18px;
		display: block;
	}
</style>
