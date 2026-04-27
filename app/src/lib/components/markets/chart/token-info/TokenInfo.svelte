<script lang="ts">
	import { browser } from '$app/environment';
	import { onMount } from 'svelte';
	import { fade, fly } from 'svelte/transition';

	type Stat = { label: string; value: string; positive?: boolean; negative?: boolean };

	interface Props {
		/** Token contract address (or any string) copied when the user clicks the copy control */
		tokenAddress?: string;
	}

	let { tokenAddress = '0x422d35Cc6634C0532925a3b844Bc9e7595f0bEb' }: Props = $props();

	/** Toast visible for this long; check clears earlier so exit animations don’t overlap */
	const COPY_TOAST_MS = 2000;
	const COPY_CHECK_ENDS_BEFORE_TOAST_MS = 320;

	let copyCheckVisible = $state(false);
	let copyToastVisible = $state(false);
	let isHovered = $state(false);
	let checkTimer: ReturnType<typeof setTimeout> | undefined;
	let toastTimer: ReturnType<typeof setTimeout> | undefined;

	let rightEl = $state<HTMLDivElement | undefined>();
	let canScrollLeft = $state(false);
	let canScrollRight = $state(false);

	let nameEl = $state<HTMLParagraphElement | undefined>();
	let nameOverflow = $state(0);

	onMount(() => {
		return () => {
			if (checkTimer !== undefined) clearTimeout(checkTimer);
			if (toastTimer !== undefined) clearTimeout(toastTimer);
		};
	});

	function updateScrollState() {
		if (!rightEl) return;
		const { scrollLeft, scrollWidth, clientWidth } = rightEl;
		canScrollLeft = scrollLeft > 0;
		canScrollRight = scrollLeft + clientWidth < scrollWidth - 1;
	}

	$effect(() => {
		if (!browser || !rightEl) return;
		updateScrollState();
		const ro = new ResizeObserver(updateScrollState);
		ro.observe(rightEl);
		return () => ro.disconnect();
	});

	$effect(() => {
		if (!browser || !nameEl) return;
		const track = nameEl.firstElementChild as HTMLElement | null;
		const measure = () => {
			if (!nameEl) return;
			nameOverflow = Math.max(0, nameEl.scrollWidth - nameEl.clientWidth);
		};
		measure();
		const ro = new ResizeObserver(measure);
		ro.observe(nameEl);
		if (track) ro.observe(track);
		return () => ro.disconnect();
	});

	async function handleCopy() {
		if (!browser) return;
		try {
			await navigator.clipboard.writeText(tokenAddress);
			copyCheckVisible = true;
			copyToastVisible = true;
			if (checkTimer !== undefined) clearTimeout(checkTimer);
			if (toastTimer !== undefined) clearTimeout(toastTimer);
			const checkMs = Math.max(0, COPY_TOAST_MS - COPY_CHECK_ENDS_BEFORE_TOAST_MS);
			checkTimer = setTimeout(() => {
				copyCheckVisible = false;
				checkTimer = undefined;
			}, checkMs);
			toastTimer = setTimeout(() => {
				copyToastVisible = false;
				toastTimer = undefined;
			}, COPY_TOAST_MS);
		} catch {
			/* clipboard denied or unavailable */
		}
	}

	const stats: Stat[] = [
		{ label: 'Price GBP', value: '£ 1.6100' },
		{ label: 'Price sETH', value: '♢ 0.0805' },
		{ label: 'Depth', value: '£ 1.1m' },
		{ label: 'Mcap', value: '£ 16.10m' },
		{ label: 'FDV', value: '£ 32.20m' },
		{ label: '24h change', value: '+0.1502 / +10.28%', positive: true },
		{ label: '24h volume', value: '£ 33,894,612' },
		{ label: 'Staked', value: '£ 3,954,354' },
		{ label: 'PPM', value: '87.36' },
		{ label: 'PBR', value: '♢ 0.4261' },
		{ label: 'Funding', value: '0.0100 (00:06:56)' }
	];
</script>

<div class="token-info">
	<div class="token-info-left">
		<img src="/tokens/playerToken.svg" alt="Player Token" class="token-image" />
		<div class="token-name">
			<p
				class="token-name-text"
				class:token-name-text--scrolling={nameOverflow > 0}
				style:--marquee-distance="{-nameOverflow}px"
				bind:this={nameEl}
			>
				<span class="token-name-text-track">G. Magalhaes <span style="font-size: 10px; color: var(--color-text-muted);">mGABR</span></span>
			</p>
			<p class="token-club-position label-eyebrow" style="font-size: 11px; text-transform: none;">ARS<span class="sidebar-footer-sep" aria-hidden="true">·</span>c-Defence</p>
		</div>
		<div class="divider"></div>
		<button
			type="button"
			class="copy-button"
			onclick={handleCopy}
			onmouseenter={() => (isHovered = true)}
			onmouseleave={() => (isHovered = false)}
			aria-label={copyToastVisible ? 'Address copied to clipboard' : 'Copy token contract address'}
		>
			{#if copyCheckVisible}
				<i class="fa-solid fa-check copy-button-icon" aria-hidden="true"></i>
			{:else if copyToastVisible}
				<i class="fa-solid fa-copy copy-button-icon" style="opacity: 0;" aria-hidden="true"></i>
			{:else}
				<span class="copy-button-text-stack">
					{#if isHovered}
						<i
							class="fa-solid fa-copy copy-button-text"
							in:fade={{ duration: 140 }}
							out:fade={{ duration: 140 }}
							aria-hidden="true"
						></i>
					{:else}
						<span
							class="copy-button-text"
							style="font-size: 10px; color: var(--color-text-muted);"
							in:fade={{ duration: 140 }}
							out:fade={{ duration: 140 }}
						>
							{tokenAddress.slice(0, 4)}
						</span>
					{/if}
				</span>
			{/if}
		</button>
	</div>
	<div class="token-info-right-shell">
		<div
			class="token-info-right"
			bind:this={rightEl}
			onscroll={updateScrollState}
		>
			{#each stats as item}
				<div class="token-info-right-item">
					<p class="token-info-right-item-label label-eyebrow">{item.label}</p>
					<p
						class="token-info-right-item-value"
						class:token-info-right-item-value--positive={item.positive === true}
						class:token-info-right-item-value--negative={item.negative === true}
					>
						{item.value}
					</p>
				</div>
			{/each}
		</div>
		<div
			class="scroll-edge scroll-edge--left"
			class:scroll-edge--active={canScrollLeft}
			aria-hidden="true"
		>
			<i class="fa-solid fa-ellipsis-vertical" aria-hidden="true"></i>
		</div>
		<div
			class="scroll-edge scroll-edge--right"
			class:scroll-edge--active={canScrollRight}
			aria-hidden="true"
		>
			<i class="fa-solid fa-ellipsis-vertical" aria-hidden="true"></i>
		</div>
	</div>
</div>

{#if copyToastVisible}
	<div class="copy-popup-host">
		<div
			class="copy-popup"
			role="status"
			aria-live="polite"
			in:fly={{ y: 14, duration: 220 }}
			out:fade={{ duration: 180 }}
		>
			Copied <span style="color: var(--color-text-muted); margin-left: 5px;">{tokenAddress.slice(0, 6)}...{tokenAddress.slice(-4)}</span>
		</div>
	</div>
{/if}

<style>
	.copy-popup-host {
		position: fixed;
		left: 0;
		right: 0;
		bottom: max(24px, env(safe-area-inset-bottom, 0px));
		z-index: 10000;
		display: flex;
		justify-content: center;
		align-items: center;
		pointer-events: none;
	}

	.copy-popup {
		padding: 10px 15px;
		border-radius: var(--radius-pill);
		border: 1px solid var(--color-border-strong);
		background-color: var(--color-surface-elevated);
		box-shadow: 0 8px 24px rgba(0, 0, 0, 0.4);
		color: #d6d6d6;
	}

	.token-info {
		height: 60px;
		width: 100%;
		background-color: var(--color-surface-elevated);
		border-bottom: 1px solid var(--color-border);
		display: flex;
		flex-direction: row;
		align-items: stretch;
		justify-content: flex-start;
		min-width: 0;
		cursor: default;
	}

	.token-info-left {
		height: 100%;
		display: flex;
		flex-direction: row;
		align-items: center;
		justify-content: flex-start;
		flex-shrink: 0;
		border-right: 1px solid var(--color-border);
		padding: 0 20px;
		gap: 15px;
	}

	.token-name {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		justify-content: center;
		gap: 4px;
	}

	.token-name p {
		margin: 0;
		padding: 0;
		width: fit-content;
		text-align: left;
		line-height: 1;
		margin-right: 10px;
	}

	.token-image {
		width: 30px;
		height: 30px;
		object-fit: cover;
		border-radius: 5px;
		background: linear-gradient(to bottom, #202020 -20%, #151515 100%);
		border: 1px solid var(--color-border);
	}

	.token-name .token-name-text {
		font-size: 14px; /* make responsive 16/14 */
		font-weight: 400;
		letter-spacing: 1px;
		line-height: 1.2;
		color: var(--color-text);
		width: 120px;
		overflow: hidden;
		white-space: nowrap;
	}

	.token-name-text-track {
		display: inline-block;
	}

	.token-name-text--scrolling .token-name-text-track {
		animation: token-name-marquee 8s ease-in-out infinite;
	}

	.token-name-text--scrolling:hover .token-name-text-track {
		animation-play-state: paused;
	}

	@keyframes token-name-marquee {
		0%,
		10% {
			transform: translateX(0);
		}
		50%,
		80% {
			transform: translateX(var(--marquee-distance, 0));
		}
		100% {
			transform: translateX(0);
		}
	}

	@media (prefers-reduced-motion: reduce) {
		.token-name-text--scrolling .token-name-text-track {
			animation: none;
		}
		.token-name .token-name-text--scrolling {
			text-overflow: ellipsis;
		}
	}

	.token-club-position {
		font-size: 12px;
		font-weight: 400;
		letter-spacing: 1px;
		color: var(--color-text-muted);
	}

	.divider {
		width: 1px;
		height: 100%;
		background-color: var(--color-border);
		margin-left: 10px;
	}

	.copy-button {
		all: unset;
		box-sizing: border-box;
		display: inline-flex;
		align-items: center;
		justify-content: center;
		margin-left: 5px;
		cursor: pointer;
		width: 28px;
		height: 20px;
	}

	.copy-button-icon {
		font-size: 12px;
		color: var(--color-text-muted);
		transition: color var(--transition-base);
		pointer-events: none;
	}

	.copy-button-text-stack {
		display: inline-grid;
		place-items: center;
		width: 100%;
		height: 100%;
	}

	.copy-button-text-stack > .copy-button-text {
		grid-area: 1 / 1;
	}

	.copy-button-text {
		font-size: 12px;
		font-weight: 400;
		letter-spacing: 1px;
		color: var(--color-text-muted);
		transition: color var(--transition-base);
		pointer-events: none;
		white-space: nowrap;
	}

	.copy-button:active .copy-button-icon {
		opacity: 0.7;
	}

	.token-info-right-shell {
		position: relative;
		flex: 1;
		min-width: 0;
		height: 100%;
	}

	.token-info-right {
		box-sizing: border-box;
		width: 100%;
		height: 100%;
		display: flex;
		flex-direction: row;
		flex-wrap: nowrap;
		align-items: center;
		justify-content: flex-start;
		gap: 30px;
		padding: 0 30px 0 20px;
		overflow-x: auto;
	}

	.scroll-edge {
		position: absolute;
		top: 0;
		bottom: -1px;
		width: 8px;
		background: var(--color-surface-muted);
		opacity: 0;
		transition: opacity var(--transition-base);
		pointer-events: none;
		display: flex;
		align-items: center;
		justify-content: center;
		border-bottom: 1px solid var(--color-border);
	}

	.scroll-edge i {
		font-size: 8px;
		color: var(--color-text-faded);
		transition: color var(--transition-base);
		pointer-events: none;
	}

	.scroll-edge--left {
		left: 0;
		border-right: 1px solid var(--color-border-light);
	}

	.scroll-edge--right {
		right: 0;
		border-left: 1px solid var(--color-border-light);
	}

	.scroll-edge--active {
		opacity: 1;
	}

	.token-info-right::-webkit-scrollbar {
		height: 2px;
	}

	.token-info-right::-webkit-scrollbar-track {
		background: transparent;
		border-radius: 0;
	}

	.token-info-right::-webkit-scrollbar-thumb {
		background: var(--color-border-strong);
		border-radius: 1px;
	}

	.token-info-right-item {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		justify-content: center;
		flex: 0 0 auto;
		gap: 4px;
		min-width: max-content;
		margin-bottom: 1px;
	}

	.token-info-right-item p {
		margin: 0;
		padding: 0;
		width: fit-content;
		text-align: left;
		line-height: 1;
	}

	.token-info-right-item-label {
		text-align: center;
		white-space: nowrap;
		font-size: 9px;
	}

	.token-info-right-item-value {
		margin: 0;
		padding: 0;
		font-size: var(--text-sm);
		font-weight: 400;
		letter-spacing: var(--tracking-default);
		color: var(--color-text);
		text-align: center;
		white-space: nowrap;
	}

	.token-info-right-item-value--positive {
		color: #198176;
	}

	.token-info-right-item-value--negative {
		color: #ae323e99;
	}

	.sidebar-footer-sep {
		color: var(--color-text-faded);
		font-size: 11px;
		user-select: none;
		margin: 0 5px;
	}
</style>
