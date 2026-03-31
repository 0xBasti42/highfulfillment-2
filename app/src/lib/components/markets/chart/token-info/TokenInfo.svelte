<script lang="ts">
	import { browser } from '$app/environment';
	import { onMount } from 'svelte';
	import { fade, fly } from 'svelte/transition';

	type Stat = { label: string; value: string; positive?: boolean; negative?: boolean };

	interface Props {
		/** Token contract address (or any string) copied when the user clicks the copy control */
		tokenAddress?: string;
	}

	let { tokenAddress = '0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb' }: Props = $props();

	/** Toast visible for this long; check clears earlier so exit animations don’t overlap */
	const COPY_TOAST_MS = 2000;
	const COPY_CHECK_ENDS_BEFORE_TOAST_MS = 320;

	let copyCheckVisible = $state(false);
	let copyToastVisible = $state(false);
	let checkTimer: ReturnType<typeof setTimeout> | undefined;
	let toastTimer: ReturnType<typeof setTimeout> | undefined;

	onMount(() => {
		return () => {
			if (checkTimer !== undefined) clearTimeout(checkTimer);
			if (toastTimer !== undefined) clearTimeout(toastTimer);
		};
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
		{ label: 'Liquidity', value: '£ 1.1m' },
		{ label: 'FDV', value: '£ 17.71m' },
		{ label: 'Mcap', value: '£ 16.10m' },
		{ label: '24h change', value: '+0.1502 / +10.28%', positive: true },
		{ label: '24h volume', value: '£ 33,894,612' },
		{ label: 'Staked', value: '£ 3,954,354' },
		{ label: 'PPM', value: '87.36' },
		{ label: 'ePBR', value: '♢ 0.4261' },
		{ label: 'Funding', value: '0.0100 (00:06:56)' }
	];
</script>

<div class="token-info">
	<div class="token-info-left">
		<img src="/tokens/playerToken.svg" alt="Player Token" class="token-image" />
		<div class="token-name">
			<p class="token-name-text">D. Rice</p>
			<p class="token-club-position">ARS / Midfield</p>
		</div>
		<button
			type="button"
			class="copy-button"
			class:copy-button--copied={copyCheckVisible}
			onclick={handleCopy}
			aria-label={copyToastVisible ? 'Address copied to clipboard' : 'Copy token contract address'}
		>
			{#if copyCheckVisible}
				<i class="fa-solid fa-check copy-button-icon" aria-hidden="true"></i>
			{:else if copyToastVisible}
				<i class="fa-solid fa-copy copy-button-icon" style="opacity: 0;" aria-hidden="true"></i>
			{:else}
				<p class="copy-button-text">Copy</p>
			{/if}
		</button>
	</div>
	<div class="token-info-right">
		{#each stats as item}
			<div class="token-info-right-item">
				<p class="token-info-right-item-label">{item.label}</p>
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
		gap: 3px;
	}

	.token-name p {
		margin: 0;
		padding: 0;
		width: fit-content;
		text-align: left;
		line-height: 1;
	}

	.token-image {
		width: 30px;
		height: 30px;
		object-fit: cover;
		border-radius: 5px;
		background: linear-gradient(to bottom, #202020 -20%, #151515 100%);
		border: 1px solid var(--color-border);
	}

	.token-name-text {
		font-size: 16px; /* make responsive 16/14 */
		font-weight: 400;
		letter-spacing: 1px;
		color: var(--color-text);
	}

	.token-club-position {
		font-size: 12px;
		font-weight: 400;
		letter-spacing: 1px;
		color: var(--color-text-muted);
	}

	.copy-button {
		all: unset;
		box-sizing: border-box;
		display: inline-flex;
		align-items: center;
		justify-content: center;
		margin-left: 10px;
		cursor: pointer;
		opacity: 0;
		transition: opacity var(--transition-base);
		width: 20px;
	}

	.copy-button-icon {
		font-size: 12px;
		color: var(--color-text-muted);
		transition: color var(--transition-base);
		pointer-events: none;
	}

	.copy-button-text {
		font-size: var(--text-xs);
		font-weight: 400;
		letter-spacing: 1px;
		color: var(--color-text-muted);
		transition: color var(--transition-base);
		pointer-events: none;
	}

	.token-info-left:hover .copy-button {
		opacity: 1;
	}

	.token-info-left:hover .copy-button:hover .copy-button-icon {
		color: #999999;
	}

	.token-info-left:hover .copy-button:active .copy-button-icon {
		opacity: 0.7;
	}

	.copy-button--copied {
		opacity: 1;
	}

	.copy-button--copied .copy-button-icon {
		color: #999999;
	}

	.token-info-right {
		height: 100%;
		flex: 1;
		min-width: 0;
		display: flex;
		flex-direction: row;
		flex-wrap: nowrap;
		align-items: center;
		justify-content: flex-start;
		gap: 30px;
		padding: 0 20px;
		overflow-x: auto;
		-ms-overflow-style: none;
		scrollbar-width: none;
	}

	.token-info-right::-webkit-scrollbar {
		display: none;
	}

	.token-info-right:last-child {
		padding-right: 60px;
	}

	.token-info-right-item {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		justify-content: center;
		flex: 0 0 auto;
		gap: 6px;
		min-width: max-content;
	}

	.token-info-right-item p {
		margin: 0;
		padding: 0;
		width: fit-content;
		text-align: left;
		line-height: 1;
	}

	.token-info-right-item-label {
		margin: 0;
		padding: 0;
		font-size: var(--text-xs);
		font-weight: 400;
		letter-spacing: var(--tracking-default);
		color: var(--color-text-muted);
		text-align: center;
		white-space: nowrap;
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
</style>
