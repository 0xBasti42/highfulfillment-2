<script lang="ts">
	import { network, type NetworkId } from '$lib/state/network.svelte';

	let isOpen = $state(false);
	let rootEl = $state<HTMLDivElement | undefined>();

	function toggle() {
		isOpen = !isOpen;
	}

	function close() {
		isOpen = false;
	}

	function select(id: NetworkId) {
		network.select(id);
		close();
	}

	/* Close on outside click and Escape.
	   pointerdown fires before click, so the panel disappears before any
	   downstream click-handler sees the event — important so e.g. clicking
	   the Connect button doesn't first toggle the menu and then trigger
	   the connect flow on the same gesture. */
	$effect(() => {
		if (!isOpen) return;
		function onPointerDown(event: PointerEvent) {
			if (!rootEl) return;
			if (!rootEl.contains(event.target as Node)) close();
		}
		function onKey(event: KeyboardEvent) {
			if (event.key === 'Escape') close();
		}
		window.addEventListener('pointerdown', onPointerDown);
		window.addEventListener('keydown', onKey);
		return () => {
			window.removeEventListener('pointerdown', onPointerDown);
			window.removeEventListener('keydown', onKey);
		};
	});
</script>

<div class="network-selector" bind:this={rootEl}>
	<button
		type="button"
		class="trigger"
		class:trigger--open={isOpen}
		aria-haspopup="listbox"
		aria-expanded={isOpen}
		aria-label="Select network"
		onclick={toggle}
	>
		<span class="trigger-icon-wrap">
			<img class="trigger-icon" src={network.current.iconSrc} alt={network.current.iconAlt} />
		</span>
		<span class="trigger-name">{network.current.name}</span>
		<i class="fa-solid fa-chevron-down trigger-chevron" aria-hidden="true"></i>
	</button>

	{#if isOpen}
		<ul class="panel" role="listbox" aria-label="Available networks">
			{#each network.networks as net (net.id)}
				{@const isSelected = net.id === network.id}
				<li>
					<button
						type="button"
						class="option"
						class:option--selected={isSelected}
						role="option"
						aria-selected={isSelected}
						onclick={() => select(net.id)}
					>
						<span class="option-icon-wrap">
							<img class="option-icon" src={net.iconSrc} alt={net.iconAlt} />
						</span>
						<span class="option-name">{net.name}</span>
						{#if isSelected}
							<i class="fa-solid fa-check option-check" aria-hidden="true"></i>
						{/if}
					</button>
				</li>
			{/each}
		</ul>
	{/if}
</div>

<style>
	.network-selector {
		position: relative;
		display: inline-flex;
		align-items: center;
	}

	/* Trigger inherits the existing `.active-chain` pill aesthetic (muted
	   surface, pill radius, 5px gap) and adds the chevron interaction
	   signature from Trade.svelte's `.asset-dropdown`: progressive dip
	   on hover/active, brightening through faded → muted → text, plus a
	   180° flip when the panel is open. */
	.trigger {
		all: unset;
		box-sizing: border-box;
		display: inline-flex;
		align-items: center;
		gap: 5px;
		height: 25px;
		padding: 0 10px 0 5px;
		background-color: var(--color-surface-muted);
		border: 1px solid transparent;
		border-radius: var(--radius-pill);
		cursor: pointer;
		transition:
			background-color var(--transition-base),
			border-color var(--transition-base);
	}

	.trigger:hover {
		border-color: var(--color-border);
	}

	.trigger:active {
		background-color: var(--color-surface);
	}

	.trigger--open {
		background-color: var(--color-surface);
		border-color: var(--color-border-strong);
	}

	.trigger-icon-wrap {
		display: inline-flex;
		width: 15px;
		height: 15px;
		border-radius: 3px;
		overflow: hidden;
	}

	.trigger-icon {
		width: 100%;
		height: 100%;
		display: block;
	}

	.trigger-name {
		font-size: 11px;
		font-weight: 400;
		letter-spacing: var(--tracking-default);
		color: var(--color-text);
		line-height: 1;
	}

	.trigger-chevron {
		margin-left: 2px;
		font-size: 9px;
		color: var(--color-text-faded);
		transition:
			color var(--transition-base),
			transform var(--transition-fast);
	}

	.trigger:hover .trigger-chevron {
		color: var(--color-text-muted);
		transform: translateY(1px);
	}

	.trigger:active .trigger-chevron {
		color: var(--color-text);
		transform: translateY(2px);
	}

	/* When open, the chevron flips upward to lock in "menu is open"
	   semantics — overrides the hover/active translate via source order. */
	.trigger--open .trigger-chevron,
	.trigger--open:hover .trigger-chevron,
	.trigger--open:active .trigger-chevron {
		color: var(--color-text);
		transform: rotate(180deg);
	}

	/* Panel is anchored to the right edge of the trigger so it doesn't
	   spill outside the header on the right-hand side of the viewport.
	   `top: calc(100% + 6px)` matches the visual rhythm of the 50px
	   header bar — close enough to feel attached, far enough to read
	   as a separate surface. */
	.panel {
		position: absolute;
		top: calc(100% + 6px);
		right: 0;
		z-index: 50;
		min-width: 160px;
		margin: 0;
		padding: 4px;
		list-style: none;
		background-color: var(--color-surface-elevated);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		box-shadow: 0 8px 24px -8px rgba(0, 0, 0, 0.5);
	}

	.option {
		all: unset;
		box-sizing: border-box;
		display: flex;
		align-items: center;
		gap: 8px;
		width: 100%;
		height: 32px;
		padding: 0 8px;
		border-radius: var(--radius-sm);
		cursor: pointer;
		transition: background-color var(--transition-fast);
	}

	.option:hover {
		background-color: var(--color-menu-hover);
	}

	.option--selected {
		background-color: var(--color-surface-muted);
	}

	.option-icon-wrap {
		display: inline-flex;
		width: 16px;
		height: 16px;
		border-radius: 3px;
		overflow: hidden;
		flex-shrink: 0;
	}

	.option-icon {
		width: 100%;
		height: 100%;
		display: block;
	}

	.option-name {
		flex: 1;
		font-size: 12px;
		font-weight: 400;
		letter-spacing: var(--tracking-default);
		color: var(--color-text);
		line-height: 1;
	}

	.option-check {
		font-size: 10px;
		color: var(--color-primary-light);
	}
</style>
