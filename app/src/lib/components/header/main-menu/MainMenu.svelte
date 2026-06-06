<script lang="ts">
	import { browser } from '$app/environment';
	import { page } from '$app/state';
	import { tick } from 'svelte';

	const navItems = [
		{ href: '/markets', label: 'Markets' },
		{ href: '/vaults', label: 'Vaults' },
		// { href: '/binaries', label: 'Binaries' },
		{ href: '/fixtures', label: 'Fixtures' }
	] as const;

	function isActive(href: string): boolean {
		const path = page.url.pathname;
		return path === href || path.startsWith(href + '/');
	}

	let containerEl = $state<HTMLDivElement | undefined>();
	let indicatorLeft = $state(0);
	let indicatorWidth = $state(0);

	function syncIndicator() {
		if (!browser || !containerEl) return;
		const active = containerEl.querySelector<HTMLElement>('a.active');
		if (!active) {
			indicatorWidth = 0;
			return;
		}
		const c = containerEl.getBoundingClientRect();
		const a = active.getBoundingClientRect();
		indicatorLeft = a.left - c.left;
		indicatorWidth = a.width;
	}

	$effect(() => {
		page.url.pathname;
		containerEl;
		if (!browser || !containerEl) return;
		tick().then(syncIndicator);
	});

	$effect(() => {
		if (!browser || !containerEl) return;
		const ro = new ResizeObserver(() => syncIndicator());
		ro.observe(containerEl);
		tick().then(syncIndicator);
		return () => ro.disconnect();
	});
</script>

<div class="main-menu" bind:this={containerEl}>
	<div class="main-menu-row">
		{#each navItems as item}
			<div class="main-menu-item">
				<a href={item.href} class:active={isActive(item.href)}>{item.label}</a>
			</div>
		{/each}
	</div>
	<!-- Single gradient track; position/width follow the active link -->
	<div
		class="main-menu-indicator"
		class:main-menu-indicator--hidden={indicatorWidth <= 0}
		style:left="{indicatorLeft}px"
		style:width="{indicatorWidth}px"
		aria-hidden="true"
	></div>
</div>

<style>
	.main-menu {
		position: relative;
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		margin-left: 20px;
		height: 50px;
	}

	.main-menu-row {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 25px;
		padding: 0;
	}

	a {
		padding: 0;
	}

	a.active {
		color: #d6d6d6;
	}

	.main-menu-indicator {
		position: absolute;
		bottom: -0;
		left: 0;
		height: 1px;
		border-radius: 1px;
		background: radial-gradient(circle at 50% 35%, var(--color-primary-light) 0%, var(--color-primary) 75%);
		transition:
			left 0.32s cubic-bezier(0.22, 1, 0.36, 1),
			width 0.32s cubic-bezier(0.22, 1, 0.36, 1),
			opacity 0.2s ease;
		pointer-events: none;
		will-change: left, width;
	}

	.main-menu-indicator--hidden {
		opacity: 0;
	}
</style>
