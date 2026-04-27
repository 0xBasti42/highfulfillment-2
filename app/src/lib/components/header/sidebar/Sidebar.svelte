<script lang="ts">
	import { fade, fly } from 'svelte/transition';
	import { cubicOut } from 'svelte/easing';
	import { page } from '$app/state';
	import { sidebar } from '$lib/state/sidebar.svelte';

	type Item = { label: string; href: string };
	type Section = { title: string; items: Item[] };

	const sections: Section[] = [
		{
			title: 'Main',
			items: [
				{ label: 'Markets', href: '/markets' },
				{ label: 'Vaults', href: '/vaults' },
				{ label: 'Binaries', href: '/binaries' },
				{ label: 'Fixtures', href: '/fixtures' }
			]
		},
		{
			title: 'Account',
			items: [
				{ label: 'Sub-Accounts', href: '/account/sub-accounts' },
				{ label: 'Multisig', href: '/account/multisig' },
				{ label: 'Referral Code', href: '/account/referral' },
				{ label: 'Leaderboard', href: '/account/leaderboard' }
			]
		},
		{
			title: 'Network',
			items: [
				{ label: 'API', href: 'https://docs.highpotential.io/api' },
				{ label: 'Explorer', href: 'https://explorer.highpotential.io/' },
				{ label: 'Stats', href: 'https://stats.highpotential.io/' },
				{ label: 'Health Check', href: 'https://health.highpotential.io/' }
			]
		},
		{
			title: 'Community',
			items: [
				{ label: 'Announcements', href: '/announcements' }
			]
		},
		{
			title: 'Misc.',
			items: [
				{ label: 'Whitepaper', href: 'https://whitepaper.highpotential.io/' },
				{ label: 'Docs', href: 'https://docs.highpotential.io/' },
				{ label: 'EF Mandate', href: 'https://etherscan.io/idm?addresses=0x5642e5ff9e48e0659060aee428754a6dd10f5b08&type=1' }
			]
		}
	];

	const footerLinks: Item[] = [
		{ label: 'Terms', href: '/terms' },
		{ label: 'Privacy', href: '/privacy' },
		{ label: 'Support', href: '/support' }
	];

	function isActive(href: string): boolean {
		const path = page.url.pathname;
		return path === href || path.startsWith(href + '/');
	}

	function isExternal(href: string): boolean {
		return /^https?:\/\//i.test(href);
	}

	function onKeydown(event: KeyboardEvent) {
		if (event.key === 'Escape' && sidebar.isOpen) {
			sidebar.close();
		}
	}
</script>

<svelte:window on:keydown={onKeydown} />

{#if sidebar.isOpen}
	<!-- Tint overlay; clicking it dismisses the menu -->
	<div
		class="sidebar-overlay"
		role="presentation"
		onclick={() => sidebar.close()}
		transition:fade={{ duration: 180, easing: cubicOut }}
	></div>

	<aside
		id="app-sidebar"
		class="sidebar"
		aria-label="Primary navigation"
		transition:fly={{ x: -320, duration: 260, easing: cubicOut }}
	>
		<nav class="sidebar-body">
			{#each sections as section}
				<section class="sidebar-section">
					<h6 class="label-eyebrow" style="color: var(--color-text-faded);">{section.title}</h6>
					<ul class="sidebar-list">
					{#each section.items as item}
						{@const external = isExternal(item.href)}
						<li>
							<a
								href={item.href}
								class:active={isActive(item.href)}
								class:external
								target={external ? '_blank' : undefined}
								rel={external ? 'noopener noreferrer' : undefined}
								onclick={() => sidebar.close()}
							>
								<span class="sidebar-list-label">{item.label}</span>
								<i
									class="fa-solid sidebar-list-chevron {external
										? 'fa-arrow-up-right-from-square'
										: 'fa-chevron-right'}"
									aria-hidden="true"
								></i>
							</a>
						</li>
					{/each}
					</ul>
				</section>
			{/each}
		</nav>

		<footer class="sidebar-footer">
			{#each footerLinks as link, i}
				{@const external = isExternal(link.href)}
				<a
					href={link.href}
					target={external ? '_blank' : undefined}
					rel={external ? 'noopener noreferrer' : undefined}
					onclick={() => sidebar.close()}
				>
					{link.label}
				</a>
				{#if i < footerLinks.length - 1}
					<span class="sidebar-footer-sep" aria-hidden="true">|</span>
				{/if}
			{/each}
		</footer>
	</aside>
{/if}

<style>
	.sidebar-overlay {
		position: fixed;
		inset: 0;
		z-index: 90;
		/* "Lighter tint" over the dark surface */
		background-color: rgba(255, 255, 255, 0.04);
		backdrop-filter: blur(2px);
		-webkit-backdrop-filter: blur(2px);
		cursor: pointer;
	}

	.sidebar {
		position: fixed;
		top: 0;
		left: 0;
		height: 100vh;
		width: 280px;
		z-index: 100;
		display: flex;
		flex-direction: column;
		background-color: var(--color-surface-elevated);
		border-right: 1px solid var(--color-border);
		box-shadow: 4px 0 24px 0 rgba(0, 0, 0, 0.35);
		overflow: hidden;
	}

	.sidebar-body {
		flex: 1 1 auto;
		min-height: 0;
		overflow-y: auto;
		padding: 22px 0 16px;
		display: flex;
		flex-direction: column;
		gap: 22px;
	}

	.sidebar-section {
		display: flex;
		flex-direction: column;
		gap: 6px;
		padding: 0 18px;
	}

	.sidebar-list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: 1px;
	}

	.sidebar-list a {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 8px;
		width: 100%;
		padding: 7px 10px;
		margin: 0;
		font-size: var(--text-sm);
		color: var(--color-text-muted);
		border-radius: var(--radius-pill);
		transition: color var(--transition-base);
	}

	.sidebar-list a:hover {
		color: var(--color-text);
	}
	
	.sidebar-list a.active {
		color: var(--color-text);
	}

	.sidebar-list-label {
		flex: 1 1 auto;
		min-width: 0;
	}

	.sidebar-list-chevron {
		flex: 0 0 auto;
		font-size: 10px;
		color: var(--color-text-muted);
		opacity: 0;
		transition: opacity var(--transition-base);
	}

	.sidebar-list a:hover .sidebar-list-chevron {
		opacity: 0.4;
	}

	.sidebar-list a.active .sidebar-list-chevron {
		opacity: 1;
	}

	.sidebar-list a.external .sidebar-list-chevron {
		opacity: 0;
	}

	.sidebar-list a.external:hover .sidebar-list-chevron {
		opacity: 0.7;
	}

	.sidebar-footer {
		flex: 0 0 auto;
		display: flex;
		align-items: center;
		justify-content: center;
		gap: 4px;
		padding: 5px 10px;
		border-top: 1px solid var(--color-border);
	}

	.sidebar-footer a {
		padding: 4px 6px;
		font-size: 11px;
		color: var(--color-text-muted);
	}

	.sidebar-footer a:hover {
		color: var(--color-text);
		text-decoration: underline;
	}

	.sidebar-footer-sep {
		color: var(--color-border-strong);
		font-size: 11px;
		user-select: none;
	}
</style>
