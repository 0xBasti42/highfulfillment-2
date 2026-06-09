<script lang="ts">
	import type { Component } from 'svelte';
	import Balances from './balances/Balances.svelte';
	import Positions from './positions/Positions.svelte';
	import Orders from './orders/Orders.svelte';
	import History from './history/History.svelte';

	const tabs = ['Balances', 'Positions', 'Orders', 'History'] as const;
	type Tab = (typeof tabs)[number];

	/* Map-based component swap: `<Component />` of a `$state`-derived
	   variable is the canonical Svelte 5 pattern for "render exactly
	   one of N", and is more deterministic than an {#if/elif} chain
	   when the previous component holds any per-mount state. */
	const TAB_COMPONENTS: Record<Tab, Component> = {
		Balances,
		Positions,
		Orders,
		History
	};

	let activeTab = $state<Tab>('Balances');
</script>

<div class="position-view">
	<div class="position-view-header">
		{#each tabs as tab}
			<button
				type="button"
				class="menu-button"
				class:active={activeTab === tab}
				aria-pressed={activeTab === tab}
				onclick={() => (activeTab = tab)}
			>
				{tab}
			</button>
		{/each}
		<!-- Extends the bottom border-line to the right of the last tab. -->
		<div class="position-view-header-spacer" aria-hidden="true"></div>
	</div>

	<div class="position-view-body">
		{#key activeTab}
			{@const Component = TAB_COMPONENTS[activeTab]}
			<Component />
		{/key}
	</div>
</div>

<style>
	.position-view {
		flex: 1 1 auto;
		min-height: 0;
		display: flex;
		flex-direction: column;
	}

	.position-view-header {
		flex-shrink: 0;
		height: 35px;
		display: flex;
		flex-direction: row;
		align-items: center;
		justify-content: flex-start;
		background-color: var(--color-surface);
	}

	.position-view-body {
		flex: 1 1 auto;
		min-height: 0;
		display: flex;
		flex-direction: column;
		align-items: stretch;
	}

	.menu-button {
		all: unset;
		box-sizing: border-box;
		height: 100%;
		display: flex;
		align-items: center;
		justify-content: center;
		padding: 0 20px;
		font-size: 12px;
		font-weight: 300;
		letter-spacing: 1px;
		color: var(--color-text-muted);
		border-bottom: 1px solid var(--color-border);
		cursor: pointer;
		transition:
			background-color var(--transition-base),
			border-color var(--transition-base),
			color var(--transition-base);
	}

	/* Reserve a transparent 1px border-left on every tab except the
	   first. Painting/unpainting via the active-state rules below
	   only changes colour, never layout — no 1px geometry shift when
	   activating a tab. */
	.menu-button + .menu-button {
		border-left: 1px solid transparent;
	}

	/* Same reservation logic for the last tab's right edge — History
	   needs a right border when active to close the active surface on
	   the side that has no following sibling. */
	.menu-button:last-of-type {
		border-right: 1px solid transparent;
	}

	.menu-button:not(.active):hover {
		background-color: #20202090;
		color: var(--color-text);
	}

	.menu-button.active {
		border-bottom-color: transparent;
		background-color: var(--color-surface-elevated);
		color: var(--color-text);
	}

	/* Borders only paint around the active tab, leaving unselected
	   tabs cleanly unbordered:
	   - the tab immediately AFTER the active one (its right boundary)
	   - the active tab itself, if not first (its left boundary)
	   - last tab (History) when active gets its border-right too */
	.menu-button.active + .menu-button,
	.menu-button:not(:first-of-type).active {
		border-left-color: var(--color-border);
	}

	.menu-button:last-of-type.active {
		border-right-color: var(--color-border);
	}

	.position-view-header-spacer {
		flex: 1;
		height: 100%;
		border-bottom: 1px solid var(--color-border);
	}
</style>
