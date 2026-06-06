<script lang="ts">
	import './layout.css';
	import { page } from '$app/state';
	import { locales, localizeHref } from '$lib/paraglide/runtime';
	import AppHeader from '$lib/components/header/Header.svelte';
	import AppFooter from '$lib/components/footer/Footer.svelte';
	import Sidebar from '$lib/components/header/sidebar/Sidebar.svelte';
	import SignupModal from '$lib/components/signup-modal/SignupModal.svelte';
	import MainColumn from '$lib/components/shell/MainColumn.svelte';
	import Side from '$lib/components/shell/Side.svelte';

	let { children } = $props();
</script>

<div style="display:none">
	{#each locales as locale}
		<a href={localizeHref(page.url.pathname, { locale })}>{locale}</a>
	{/each}
</div>

<main class="app-root">
	<div class="app-layout">
		<div class="app-header-wrap">
			<AppHeader />
		</div>
		<div class="app-pages">
			<MainColumn>
				{@render children?.()}
			</MainColumn>
			<Side />
		</div>
		<div class="app-footer-wrap">
			<AppFooter />
		</div>
	</div>
	<Sidebar />
	<SignupModal />
</main>

<style>
	.app-root {
		width: 100vw;
		height: 100vh;
	}

	.app-layout {
		width: 100%;
		height: 100%;
		display: flex;
		flex-direction: column;
		align-items: stretch;
	}

	.app-header-wrap {
		width: 100%;
		height: auto;
		display: flex;
		flex-direction: column;
		align-items: stretch;
	}

	.app-pages {
		display: flex;
		flex-direction: row;
		flex: 1;
		min-height: 1224px;
		width: 100%;
		background-color: var(--color-surface-elevated);
		padding: 0;
	}

	.app-footer-wrap {
		width: 100%;
		height: auto;
		display: flex;
		flex-direction: column;
		align-items: stretch;
	}
</style>
