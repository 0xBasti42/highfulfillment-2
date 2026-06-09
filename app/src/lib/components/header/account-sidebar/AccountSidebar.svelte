<script lang="ts">
	import { fade, fly, slide } from 'svelte/transition';
	import { cubicOut } from 'svelte/easing';
	import { account } from '$lib/state/account.svelte';
	import { auth } from '$lib/state/auth.svelte';
	import {
		settings,
		type Stablecoin,
		type EthVariant
	} from '$lib/state/settings.svelte';
	import { currencyOf } from '$lib/utils/currency';
	import { truncateAddress } from '$lib/utils/address';
	import { scrollLock } from '$lib/utils/scrollLock';

	/* `$derived` so the balance card's currency sign re-renders the
	   moment the user toggles their default stablecoin below. */
	const currency = $derived(currencyOf(settings.defaultStablecoin));

	/* Driven from a const table rather than inline markup so adding a
	   fourth stablecoin (e.g. PYUSD) later is a one-line append. Icon
	   paths match the canonical asset svgs used by Trade.svelte. */
	const STABLECOIN_OPTIONS: { value: Stablecoin; label: string; icon: string }[] = [
		{ value: 'TGBP', label: 'TGBP', icon: '/tokens/tgbp-blue.svg' },
		{ value: 'USDC', label: 'USDC', icon: '/tokens/usdc.svg' },
		{ value: 'EURC', label: 'EURC', icon: '/tokens/eurc.svg' }
	];

	const ETH_VARIANT_OPTIONS: { value: EthVariant; label: string; icon: string }[] = [
		{ value: 'ETH', label: 'ETH', icon: '/tokens/eth.svg' },
		{ value: 'SETH', label: 'SETH', icon: '/tokens/seth-dec-3.svg' }
	];

	/* Tracks which row was just copied so the row's trailing icon can
	   flip to a check briefly. Single string is enough because the user
	   can only have one most-recent copy at a time. */
	let copiedKey = $state<string | null>(null);
	let copiedTimer: ReturnType<typeof setTimeout> | null = null;

	/* Settings is collapsed by default — it's configuration that users
	   set rarely, not the primary surface. In-memory only: refresh
	   resets to collapsed. Promote to localStorage in settings.svelte.ts
	   if persistence becomes important. */
	let settingsExpanded = $state(false);

	/* Body scroll lock — gated on the same composite condition as the
	   {#if} below so the lock matches the actual render state. If the
	   user signs out while the panel is open, both flip and the lock
	   releases via the cleanup return. */
	$effect(() => {
		if (account.isOpen && auth.isSignedIn) {
			scrollLock.acquire();
			return () => scrollLock.release();
		}
	});

	async function copy(value: string, key: string) {
		try {
			await navigator.clipboard.writeText(value);
			copiedKey = key;
			if (copiedTimer) clearTimeout(copiedTimer);
			copiedTimer = setTimeout(() => (copiedKey = null), 1500);
		} catch {
			/* Clipboard API can reject in insecure contexts or when the
			   page isn't focused. Silent fail keeps the UI usable;
			   we'll surface real errors if/when we add a toast layer. */
		}
	}

	function handleSignOut() {
		account.close();
		auth.signOut();
	}

	/* TODO: open the dedicated Deposit modal once that flow exists.
	   Most likely shape: a new state singleton (e.g. `deposit.open()`)
	   triggers a modal showing the user's smart wallet address + a QR
	   code + supported assets, plus a fiat onramp option. */
	function handleDeposit() {
		/* placeholder */
	}

	/* TODO: open the Withdraw modal — UserOp-builder UI for sending
	   ETH/USDC/etc from the smart wallet to an external address. Must
	   gate on `auth.isSignedIn` (already implicit here, since this
	   sidebar only renders for authenticated users). */
	function handleWithdraw() {
		/* placeholder */
	}

	function onKeydown(event: KeyboardEvent) {
		if (event.key === 'Escape' && account.isOpen) {
			account.close();
		}
	}
</script>

<svelte:window onkeydown={onKeydown} />

{#if account.isOpen && auth.isSignedIn}
	<div
		class="account-overlay"
		role="presentation"
		onclick={() => account.close()}
		transition:fade={{ duration: 180, easing: cubicOut }}
	></div>

	<aside
		id="app-account-sidebar"
		class="account"
		aria-label="Account"
		transition:fly={{ x: 320, duration: 260, easing: cubicOut }}
	>
		<header class="account-header">
			<div class="header-icon">
				<i class="fa-solid fa-wallet" aria-hidden="true"></i>
			</div>
			<div class="header-text">
				<p class="header-email">{auth.email}</p>
				<p class="header-status">
					<span class="status-dot" aria-hidden="true"></span>
					Connected
				</p>
			</div>
		</header>

		<nav class="account-body">
			<section class="account-section">
				<h6 class="label-eyebrow section-title">Balance</h6>
				<div class="balance-card">
					<div class="balance-total">
						<span class="label-eyebrow balance-label">Total value</span>
						<!-- TODO(balance): wire to a real fiat-converted portfolio
						     value. Needs (a) ETH + USDC + SETH balanceOf reads via
						     viem against the smart wallet, (b) player-token
						     positions aggregated from the markets indexer, (c) a
						     price oracle for ETH + an FX rate for the user's
						     chosen fiat. Aggregate sum lives here, prefixed with
						     the currency sign of the default stablecoin. -->
						<p class="balance-amount">{currency.sign} 0.00</p>
					</div>
					<div class="balance-divider" aria-hidden="true"></div>
					<ul class="balance-list">
						<li class="balance-row">
							<span class="balance-asset">{settings.defaultEthVariant}</span>
							<span class="balance-figure">0.0000</span>
						</li>
						<li class="balance-row">
							<span class="balance-asset">{settings.defaultStablecoin}</span>
							<span class="balance-figure">0.00</span>
						</li>
					</ul>
				</div>
				<div class="balance-actions">
					<button
						type="button"
						class="balance-action balance-action--primary"
						onclick={handleDeposit}
					>
						<span
							class="balance-action-icon balance-action-icon--deposit"
							aria-hidden="true"
						></span>
						<span>Deposit</span>
					</button>
					<button type="button" class="balance-action" onclick={handleWithdraw}>
						<span
							class="balance-action-icon balance-action-icon--withdraw"
							aria-hidden="true"
						></span>
						<span>Withdraw</span>
					</button>
				</div>
			</section>

			<section class="account-section">
				<h6 class="label-eyebrow section-title">Wallet</h6>
				<ul class="address-list">
					<li>
						<button
							type="button"
							class="address-row"
							onclick={() => copy(auth.smartWallet!, 'smart')}
						>
							<div class="address-text">
								<span class="label-eyebrow row-label">Smart Wallet</span>
								<code class="row-addr">{truncateAddress(auth.smartWallet!)}</code>
							</div>
							<i
								class="fa-solid row-icon {copiedKey === 'smart'
									? 'fa-check row-icon--copied'
									: 'fa-copy'}"
								aria-hidden="true"
							></i>
						</button>
					</li>
					<li>
						<button
							type="button"
							class="address-row"
							onclick={() => copy(auth.ownerEoa!, 'eoa')}
						>
							<div class="address-text">
								<span class="label-eyebrow row-label">Owner EOA</span>
								<code class="row-addr">{truncateAddress(auth.ownerEoa!)}</code>
							</div>
							<i
								class="fa-solid row-icon {copiedKey === 'eoa'
									? 'fa-check row-icon--copied'
									: 'fa-copy'}"
								aria-hidden="true"
							></i>
						</button>
					</li>
				</ul>
			</section>

			<section class="account-section">
				<button
					type="button"
					class="section-toggle"
					aria-expanded={settingsExpanded}
					aria-controls="account-settings-content"
					onclick={() => (settingsExpanded = !settingsExpanded)}
				>
					<h6 class="label-eyebrow section-title">Settings</h6>
					<i
						class="fa-solid fa-chevron-down section-toggle-chevron"
						class:section-toggle-chevron--open={settingsExpanded}
						aria-hidden="true"
					></i>
				</button>
				{#if settingsExpanded}
					<div
						id="account-settings-content"
						class="section-toggle-content"
						transition:slide={{ duration: 200, easing: cubicOut }}
					>
						<div class="setting-row">
							<div class="setting-label-line">
								<span class="label-eyebrow setting-label">Default ETH</span>
								<button
									type="button"
									class="info-tip"
									aria-label="About SETH"
									aria-describedby="default-eth-tip"
								>
									<i class="fa-solid fa-circle-info" aria-hidden="true"></i>
								</button>
							</div>
							<div class="segmented" role="radiogroup" aria-label="Default ETH">
								{#each ETH_VARIANT_OPTIONS as option (option.value)}
									{@const active = settings.defaultEthVariant === option.value}
									<button
										type="button"
										class="segmented-option"
										class:segmented-option--active={active}
										role="radio"
										aria-checked={active}
										onclick={() => settings.setDefaultEthVariant(option.value)}
									>
										<img src={option.icon} alt="" class="segmented-icon" />
										<span>{option.label}</span>
									</button>
								{/each}
							</div>
							<!-- Absolutely positioned; sits visually above the row when
							     the info button is hovered or keyboard-focused. Revealed
							     via the `:has()` rule in the style block below — no
							     JS state needed for a pure hover affordance. -->
							<div id="default-eth-tip" role="tooltip" class="setting-tooltip">
								SETH is ETH/100, and it turns TVL into an additional source of revenue for
								verified applications across the EVM.
							</div>
						</div>
						<div class="setting-row">
							<div class="setting-label-line">
								<span class="label-eyebrow setting-label">Default stablecoin</span>
								<button
									type="button"
									class="info-tip"
									aria-label="About stablecoins"
									aria-describedby="default-stablecoin-tip"
								>
									<i class="fa-solid fa-circle-info" aria-hidden="true"></i>
								</button>
							</div>
							<div class="segmented" role="radiogroup" aria-label="Default stablecoin">
								{#each STABLECOIN_OPTIONS as option (option.value)}
									{@const active = settings.defaultStablecoin === option.value}
									<button
										type="button"
										class="segmented-option"
										class:segmented-option--active={active}
										role="radio"
										aria-checked={active}
										onclick={() => settings.setDefaultStablecoin(option.value)}
									>
										<img src={option.icon} alt="" class="segmented-icon" />
										<span>{option.label}</span>
									</button>
								{/each}
							</div>
							<div id="default-stablecoin-tip" role="tooltip" class="setting-tooltip">
								A 1:1 pegged digital asset that is fully backed by underlying fiat collateral.
							</div>
						</div>
					</div>
				{/if}
			</section>
		</nav>

		<footer class="account-footer">
			<button type="button" class="signOut" onclick={handleSignOut}>
				<i class="fa-solid fa-arrow-right-from-bracket" aria-hidden="true"></i>
				<span>Sign out</span>
			</button>
		</footer>
	</aside>
{/if}

<style>
	/* Backdrop + panel recipe mirrors the main Sidebar so the two
	   sliding surfaces feel like siblings: faint white tint at 0.04
	   alpha + 2px blur, no shadow on the panel itself. */
	.account-overlay {
		position: fixed;
		inset: 0;
		z-index: 90;
		background-color: rgba(255, 255, 255, 0.04);
		backdrop-filter: blur(2px);
		-webkit-backdrop-filter: blur(2px);
		cursor: pointer;
	}

	/* Anchored to the right edge — slides in from outside the viewport
	   so the entry direction matches its origin (the wallet pill at
	   header-right). Border on the LEFT edge (vs the main sidebar's
	   right edge) for the same reason. */
	.account {
		position: fixed;
		top: 0;
		right: 0;
		height: 100vh;
		width: 320px;
		z-index: 100;
		display: flex;
		flex-direction: column;
		background-color: var(--color-surface-elevated);
		border-left: 1px solid var(--color-border);
		overflow: hidden;
	}

	/* ---- Header (avatar + email + status) ---- */
	.account-header {
		display: flex;
		align-items: center;
		gap: 12px;
		padding: 22px 18px 18px;
		border-bottom: 1px solid var(--color-border);
	}

	/* Same teal-gradient pill as the header wallet trigger — keeps the
	   "this surface belongs to that trigger" lineage visible. */
	.header-icon {
		flex-shrink: 0;
		width: 36px;
		height: 36px;
		display: inline-flex;
		align-items: center;
		justify-content: center;
		background: linear-gradient(
			to left,
			var(--color-primary-light) -20%,
			var(--color-primary) 100%
		);
		border-radius: var(--radius-pill);
		color: var(--color-text-inverse);
		font-size: 14px;
	}

	.header-text {
		min-width: 0;
		flex: 1;
		display: flex;
		flex-direction: column;
		gap: 2px;
	}

	.header-email {
		margin: 0;
		font-size: var(--text-sm);
		color: var(--color-text);
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.header-status {
		margin: 0;
		font-size: 11px;
		color: var(--color-text-muted);
		display: inline-flex;
		align-items: center;
		gap: 6px;
	}

	.status-dot {
		width: 6px;
		height: 6px;
		border-radius: 50%;
		background-color: var(--color-primary-light);
		box-shadow: 0 0 6px var(--color-primary-light);
	}

	/* ---- Body sections ---- */
	.account-body {
		flex: 1 1 auto;
		min-height: 0;
		overflow-y: auto;
		padding: 18px 0;
		display: flex;
		flex-direction: column;
		gap: 22px;
	}

	.account-section {
		display: flex;
		flex-direction: column;
		gap: 10px;
		padding: 0 18px;
	}

	.section-title {
		color: var(--color-text-faded);
	}

	/* Click-target for collapsible section headers. Wraps the whole row
	   (title + chevron) so the user has a generous target. Inherits
	   block layout via `width: 100%`. */
	.section-toggle {
		all: unset;
		width: 100%;
		display: flex;
		align-items: center;
		justify-content: space-between;
		cursor: pointer;
	}

	.section-toggle-chevron {
		font-size: 10px;
		color: var(--color-text-faded);
		transition:
			transform var(--transition-base),
			color var(--transition-base);
	}

	.section-toggle:hover .section-toggle-chevron {
		color: var(--color-text-muted);
	}

	/* 180° flip when expanded — matches the open-state chevron treatment
	   used by NetworkSelector's trigger. */
	.section-toggle-chevron--open {
		transform: rotate(180deg);
	}

	/* Content slot below the toggle. The `slide` transition on Svelte's
	   `<div>` measures content height automatically; this rule just
	   keeps the same flex-column rhythm the parent section uses, so
	   each setting-row inside still gets the 10px vertical gap. */
	.section-toggle-content {
		display: flex;
		flex-direction: column;
		gap: 10px;
	}

	/* ---- Balance card ----
	   Single non-interactive card with the total at the top, a hairline
	   separator, and a per-asset breakdown below. Same surface/border
	   recipe as the address rows so Balance and Wallet read as siblings,
	   minus the hover state because this card is display-only. */
	.balance-card {
		display: flex;
		flex-direction: column;
		gap: 12px;
		padding: 14px;
		background-color: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
	}

	.balance-total {
		display: flex;
		flex-direction: column;
		gap: 4px;
	}

	.balance-label {
		font-size: 10px;
	}

	/* Single-typeface treatment for balance figures: Inter throughout
	   (the rest of the UI uses Inter), with `tabular-nums` so digits
	   share equal advance widths and the small per-asset rows below
	   line up. To swap to mono ("financial terminal" look) instead,
	   change the `font-family` here and on `.balance-figure` to
	   `ui-monospace, 'JetBrains Mono', …` and drop `tabular-nums`. */
	.balance-amount {
		margin: 0;
		font-family: var(--font-sans);
		font-size: 20px;
		font-weight: 400;
		letter-spacing: var(--tracking-default);
		font-variant-numeric: tabular-nums;
		color: var(--color-text);
		line-height: 1;
	}

	.balance-divider {
		width: 100%;
		height: 1px;
		background-color: var(--color-border);
	}

	.balance-list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: 6px;
	}

	.balance-row {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 12px;
		font-size: 12px;
	}

	.balance-asset {
		color: var(--color-text-muted);
	}

	/* Inherits Inter from the body. `tabular-nums` aligns digit columns
	   vertically across the rows (ETH / TGBP) so values are scannable
	   without falling back to monospace. */
	.balance-figure {
		font-variant-numeric: tabular-nums;
		color: var(--color-text);
	}

	/* ---- Balance action buttons (Deposit / Withdraw) ----
	   Two equally-weighted pill buttons sitting below the balance card.
	   Same outlined-card pattern as the address rows + segmented options
	   (border, hover-brighten, surface-muted fill on hover) so the
	   sidebar's interaction language stays consistent. */
	.balance-actions {
		display: flex;
		gap: 8px;
	}

	.balance-action {
		all: unset;
		flex: 1;
		box-sizing: border-box;
		height: 36px;
		display: inline-flex;
		align-items: center;
		justify-content: center;
		gap: 8px;
		background-color: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-pill);
		color: var(--color-text);
		font-size: var(--text-sm);
		letter-spacing: var(--tracking-default);
		cursor: pointer;
		transition: all var(--transition-base);
	}

	.balance-action:hover {
		background-color: var(--color-surface-muted);
		border-color: var(--color-border-strong);
	}

	.balance-action:active {
		opacity: 0.85;
	}

	/* Custom SVG icons rendered via CSS mask so they pick up button
	   text colour rather than the SVG's own hardcoded fill (`#999` on
	   deposit, `#000` on withdraw — both invisible or wrong-coloured
	   if used as plain <img>). The mask treats the SVG as an alpha
	   stencil; the visible colour comes from `background-color`. */
	.balance-action-icon {
		display: inline-block;
		width: 14px;
		height: 14px;
		background-color: var(--color-text-muted);
		-webkit-mask-position: center;
		-webkit-mask-size: contain;
		-webkit-mask-repeat: no-repeat;
		mask-position: center;
		mask-size: contain;
		mask-repeat: no-repeat;
		transition: background-color var(--transition-base);
	}

	.balance-action-icon--deposit {
		-webkit-mask-image: url('/icons/deposit.svg');
		mask-image: url('/icons/deposit.svg');
	}

	.balance-action-icon--withdraw {
		-webkit-mask-image: url('/icons/withdraw.svg');
		mask-image: url('/icons/withdraw.svg');
	}

	.balance-action:hover .balance-action-icon {
		background-color: var(--color-text);
	}

	/* Teal-gradient primary variant of the balance action button. Same
	   geometry, swaps the outlined card surface for the global CTA
	   gradient + brightness-on-hover treatment used by the header
	   wallet pill and Trade's swap button. Source-ordered after the
	   base hover/active so the modifier's pseudo-class rules win via
	   tied specificity (both 0,2,0). */
	.balance-action--primary {
		background: linear-gradient(
			to left,
			var(--color-primary-light) -20%,
			var(--color-primary) 100%
		);
		border-color: transparent;
		color: var(--color-text-inverse);
	}

	.balance-action--primary:hover {
		background: linear-gradient(
			to left,
			var(--color-primary-light) -20%,
			var(--color-primary) 100%
		);
		border-color: transparent;
		filter: brightness(1.08);
		box-shadow: 0 0 16px -4px color-mix(in oklab, var(--color-primary-light) 40%, transparent);
	}

	.balance-action--primary:active {
		filter: brightness(0.97);
		box-shadow: none;
		opacity: 1;
		transition-duration: 80ms;
	}

	.balance-action--primary .balance-action-icon,
	.balance-action--primary:hover .balance-action-icon {
		background-color: var(--color-text-inverse);
	}

	/* ---- Address rows ---- */
	.address-list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: 8px;
	}

	/* Same card-on-surface treatment used by the modal's wallet card,
	   but clickable. Border brightens on hover (mirrors the Trade
	   .asset-dropdown pattern). */
	.address-row {
		all: unset;
		box-sizing: border-box;
		width: 100%;
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 12px;
		padding: 10px 12px;
		background-color: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		cursor: pointer;
		transition: border-color var(--transition-base);
	}

	.address-row:hover {
		border-color: var(--color-border-strong);
	}

	.address-row:active {
		opacity: 0.85;
	}

	.address-text {
		min-width: 0;
		flex: 1;
		display: flex;
		flex-direction: column;
		gap: 4px;
	}

	.row-label {
		font-size: 10px;
	}

	.row-addr {
		font-family: ui-monospace, 'JetBrains Mono', 'SFMono-Regular', Menlo, monospace;
		font-size: 12px;
		color: var(--color-text);
	}

	.row-icon {
		flex-shrink: 0;
		font-size: 12px;
		color: var(--color-text-muted);
		transition: color var(--transition-base);
	}

	.address-row:hover .row-icon {
		color: var(--color-text);
	}

	/* Flipped to the success teal so the "copied" confirmation reads
	   as a positive state rather than a hover state. Reverts to the
	   normal icon colour when copiedKey resets. */
	.row-icon--copied,
	.address-row:hover .row-icon--copied {
		color: var(--color-primary-light);
	}

	/* ---- Settings ----
	   Generic shape for a single setting: small eyebrow label + control
	   stacked below. The control itself is whatever the setting needs
	   (segmented buttons, toggle, dropdown, etc.). `position: relative`
	   so any setting-tooltip inside can anchor to the row's right edge. */
	.setting-row {
		position: relative;
		display: flex;
		flex-direction: column;
		gap: 8px;
	}

	/* Subordinate to the SETTINGS section title above — reverts to the
	   default label-eyebrow tone (`--color-text-muted`) now that the
	   heading is restored. */
	.setting-label {
		font-size: 10px;
	}

	/* Label + info tip sit on one line so the tip reads as belonging
	   to the adjacent label rather than the whole row. */
	.setting-label-line {
		display: inline-flex;
		align-items: center;
		gap: 6px;
	}

	/* `cursor: help` is the canonical affordance for "more info on
	   hover" — distinct from `pointer` (an action) and `default`
	   (informational only). */
	.info-tip {
		all: unset;
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 14px;
		height: 14px;
		color: var(--color-text-faded);
		font-size: 11px;
		cursor: help;
		transition: color var(--transition-base);
	}

	.info-tip:hover,
	.info-tip:focus-visible {
		color: var(--color-text-muted);
	}

	/* Anchored to the right of the row + above the label so a 260px
	   tooltip never overflows the 284px sidebar content area. Hidden
	   by default; revealed via the :has() rule below when the
	   adjacent info-tip is hovered or keyboard-focused. */
	.setting-tooltip {
		position: absolute;
		bottom: calc(100% + 6px);
		right: 0;
		width: 260px;
		padding: 8px 10px;
		background-color: var(--color-surface);
		border: 1px solid var(--color-border-strong);
		border-radius: var(--radius-md);
		color: var(--color-text);
		font-size: 11px;
		font-weight: 300;
		line-height: 1.45;
		letter-spacing: var(--tracking-default);
		text-transform: none;
		opacity: 0;
		pointer-events: none;
		transition: opacity var(--transition-base);
		z-index: 20;
	}

	/* `:has()` lifts the hover/focus state up to the row so the
	   tooltip (sibling of the label-line, not of the button itself)
	   can react. Widely supported as of 2024+. */
	.setting-row:has(.info-tip:hover) .setting-tooltip,
	.setting-row:has(.info-tip:focus-visible) .setting-tooltip {
		opacity: 1;
	}

	/* Segmented control: three sibling pill buttons sharing the row.
	   Inactive options sit quietly at muted text; hover brightens both
	   border and text; the active option lifts to muted-surface fill +
	   bright text + brighter border so it reads as "selected, not
	   merely hovered". Same dim-on-hover signature as Trade's
	   .asset-selector-right-item percent pills. */
	.segmented {
		display: flex;
		gap: 6px;
	}

	.segmented-option {
		all: unset;
		flex: 1;
		box-sizing: border-box;
		height: 32px;
		display: inline-flex;
		align-items: center;
		justify-content: center;
		gap: 6px;
		padding: 0 8px;
		background-color: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-pill);
		color: var(--color-text-muted);
		font-size: 11px;
		cursor: pointer;
		transition: all var(--transition-base);
	}

	.segmented-option:hover {
		border-color: var(--color-border-strong);
		color: var(--color-text);
	}

	.segmented-option--active,
	.segmented-option--active:hover {
		background-color: var(--color-surface-muted);
		border-color: var(--color-border-strong);
		color: var(--color-text);
	}

	/* Matches the rounded-square bordered treatment used by Trade's
	   asset-dropdown image and Balances' table asset images, scaled
	   down: 3px radius on a 14px icon is the same ~20% ratio Trade
	   uses (5px on 20px). Plain border, no background fallback —
	   the gradient backing is only useful on the larger 24px icons
	   in Balances where icons can fail to load and need a placeholder. */
	.segmented-icon {
		width: 14px;
		height: 14px;
		flex-shrink: 0;
		border-radius: 3px;
		border: 1px solid var(--color-border);
		object-fit: cover;
	}

	/* ---- Footer (sign out) ---- */
	.account-footer {
		flex: 0 0 auto;
		display: flex;
		align-items: center;
		justify-content: center;
		padding: 12px 18px;
		border-top: 1px solid var(--color-border);
	}

	/* Quiet destructive action: muted text by default, error-coloured
	   on hover so the user gets a clear "this is a removal" cue before
	   committing. Press dims for tactile feedback. */
	.signOut {
		all: unset;
		display: inline-flex;
		align-items: center;
		gap: 10px;
		padding: 8px 14px;
		font-size: var(--text-sm);
		color: var(--color-text-muted);
		border-radius: var(--radius-pill);
		cursor: pointer;
		transition: color var(--transition-base);
	}

	.signOut:hover {
		color: var(--color-error);
	}

	.signOut:active {
		opacity: 0.7;
	}
</style>
