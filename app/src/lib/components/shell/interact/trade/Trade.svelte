<script lang="ts">
	type TradeMode = 'exchange' | 'advanced' | 'stake';
	type TradeSide = 'input' | 'output';

	type Token = {
		image: string;
		alt: string;
		symbol: string;
	};

	type InfoSegment =
		| { kind: 'label'; text: string }
		| { kind: 'ticker'; text: string }
		| { kind: 'number'; text: string };

	type TradeSideConfig = {
		side: TradeSide;
		label: string;
		infoRight: InfoSegment[];
		tokenImage: string;
		tokenAlt: string;
		tokenSymbol: string;
		amount: string;
		setAmount: (value: string) => void;
		ariaLabel: string;
		percentOptions?: readonly number[];
	};

	const AMOUNT_PATTERN = '[0-9]*[.,]?[0-9]*';

	const MGABR: Token = {
		image: '/tokens/playerToken.svg',
		alt: 'Player Token',
		symbol: 'mGABR'
	};

	const SETH: Token = {
		image: '/tokens/seth-dec-3.svg',
		alt: 'sETH',
		symbol: 'sETH'
	};

	const ETH: Token = {
		image: '/tokens/eth.svg',
		alt: 'ETH',
		symbol: 'ETH'
	};

	const TGBP: Token = {
		image: '/tokens/tgbp-blue.svg',
		alt: 'tGBP',
		symbol: 'tGBP'
	};

	const DAI: Token = {
		image: '/tokens/dai.svg',
		alt: 'DAI',
		symbol: 'DAI'
	};

	const EURC: Token = {
		image: '/tokens/eurc.svg',
		alt: 'EURC',
		symbol: 'EURC'
	};

	const USDC: Token = {
		image: '/tokens/usdc.svg',
		alt: 'USDC',
		symbol: 'USDC'
	};

	let mode = $state<TradeMode>('exchange');
	let swapIconTurns = $state(0);
	let tokenIn = $state<Token>(ETH);
	let tokenOut = $state<Token>(MGABR);
	let sellAmount = $state('');
	let buyAmount = $state('');
	// Placeholder rate expressed as units of tokenIn per 1 tokenOut.
	// Replace with a real quote once the Quoter is wired.
	let exchangeRate = $state(1 / 0.62);

	const formattedRate = $derived(exchangeRate.toFixed(2));

	const sellSide: TradeSideConfig = $derived({
		side: 'input',
		label: 'From',
		infoRight: [
			{ kind: 'label', text: 'Balance:' },
			{ kind: 'number', text: '0.00' }
		],
		tokenImage: tokenIn.image,
		tokenAlt: tokenIn.alt,
		tokenSymbol: tokenIn.symbol,
		amount: sellAmount,
		setAmount: (value) => (sellAmount = value),
		ariaLabel: 'Amount to sell',
		percentOptions: [5, 10, 20]
	});

	const buySide: TradeSideConfig = $derived({
		side: 'output',
		label: 'To',
		infoRight: [
			{ kind: 'number', text: '1' },
			{ kind: 'ticker', text: tokenOut.symbol },
			{ kind: 'number', text: '=' },
			{ kind: 'number', text: formattedRate },
			{ kind: 'ticker', text: tokenIn.symbol }
		],
		tokenImage: tokenOut.image,
		tokenAlt: tokenOut.alt,
		tokenSymbol: tokenOut.symbol,
		amount: buyAmount,
		setAmount: (value) => (buyAmount = value),
		ariaLabel: 'Amount to buy'
	});

	function handleSwapTokens() {
		swapIconTurns += 1;
		[tokenIn, tokenOut] = [tokenOut, tokenIn];
		[sellAmount, buyAmount] = [buyAmount, sellAmount];
		exchangeRate = 1 / exchangeRate;
	}

	function selectMode(next: TradeMode) {
		mode = next;
	}
</script>

{#snippet tradeSide(config: TradeSideConfig)}
	<div class="input-output {config.side}">
		<div class="info">
			<div class="info-left">
				<p class="label-eyebrow">{config.label}</p>
			</div>
			<div class="info-right">
				{#each config.infoRight as seg}
					{#if seg.kind === 'number'}
						<p class="info-number">{seg.text}</p>
					{:else if seg.kind === 'ticker'}
						<p class="label-eyebrow info-ticker">{seg.text}</p>
					{:else}
						<p class="label-eyebrow">{seg.text}</p>
					{/if}
				{/each}
			</div>
		</div>

		<div class="asset-selector">
			<div class="asset-selector-left">
				<button type="button" class="asset-dropdown">
					<img
						src={config.tokenImage}
						alt={config.tokenAlt}
						class="asset-dropdown-left-image"
					/>
					<p class="asset-dropdown-name">{config.tokenSymbol}</p>
					<i class="fa-solid fa-chevron-down asset-dropdown-icon" aria-hidden="true"></i>
				</button>
			</div>

			{#if config.percentOptions}
				<div class="asset-selector-right">
					{#each config.percentOptions as pct (pct)}
						<button type="button" class="asset-selector-right-item">
							<p class="asset-selector-right-item-label">+{pct}%</p>
						</button>
					{/each}
				</div>
			{/if}
		</div>

		<div class="amount-selector">
			<input
				type="text"
				inputmode="decimal"
				pattern={AMOUNT_PATTERN}
				autocomplete="off"
				spellcheck="false"
				placeholder="0.00"
				class="amount-input"
				aria-label={config.ariaLabel}
				value={config.amount}
				oninput={(event) => config.setAmount(event.currentTarget.value)}
			/>
		</div>
	</div>
{/snippet}

<div class="trade">
	<div class="trade-header">
		<div class="trade-header-left">
			<button
				type="button"
				class="trade-header-left-item"
				class:active={mode === 'exchange'}
				aria-pressed={mode === 'exchange'}
				onclick={() => selectMode('exchange')}
			>
				<p class="trade-header-label">Exchange</p>
			</button>
			<div class="divider" aria-hidden="true"></div>
			<button
				type="button"
				class="trade-header-left-item"
				class:active={mode === 'advanced'}
				aria-pressed={mode === 'advanced'}
				onclick={() => selectMode('advanced')}
			>
				<p class="trade-header-label">Advanced</p>
			</button>
			<div class="divider" aria-hidden="true"></div>
		</div>
		<div class="trade-header-right">
			<div class="trade-header-right-item">
				<div class="settings-icon-container">
					<img src="/icons/settings.svg" alt="Settings" class="settings-icon" />
				</div>
			</div>
		</div>
	</div>

	{#if mode === 'exchange'}
		<div class="trade-body">
			{@render tradeSide(sellSide)}

			<div class="input-output-separator">
				<button
					type="button"
					class="swap-icon"
					aria-label="Swap input and output tokens"
					onclick={handleSwapTokens}
				>
					<img
						src="/icons/exchange.svg"
						alt=""
						aria-hidden="true"
						class="swap-icon-button"
						style="transform: rotate({swapIconTurns * 180}deg)"
					/>
				</button>
			</div>

			{@render tradeSide(buySide)}
		</div>

		<div class="trade-footer">
			<button type="button" class="swap-button">Connect</button>
			<div class="swap-info">
				<p class="swap-info-label"></p>
			</div>
		</div>
	{:else}
		<div class="trade-advanced">
			<!-- Advanced mode content goes here -->
		</div>
	{/if}
</div>

<style>
	/* ---------- Container ---------- */
	.trade {
		width: 100%;
		height: 616px;
		display: flex;
		flex-direction: column;
		align-items: stretch;
		justify-content: flex-start;
	}

	/* ---------- Header ---------- */
	.trade-header {
		background-color: var(--color-surface);
		width: 100%;
		height: 60px;
		display: flex;
		flex-direction: row;
		align-items: center;
		justify-content: space-between;
	}

	.trade-header-left {
		height: 100%;
		display: flex;
		flex-direction: row;
		align-items: center;
		justify-content: flex-start;
	}

	.trade-header-left-item {
		all: unset;
		box-sizing: border-box;
		height: 100%;
		display: flex;
		flex-direction: row;
		align-items: center;
		justify-content: center;
		gap: 10px;
		padding: 0 20px;
		border-bottom: 1px solid var(--color-border);
		cursor: pointer;
		transition:
			background-color var(--transition-base),
			border-color var(--transition-base),
			color var(--transition-base);
	}

	.trade-header-left-item.active {
		border-bottom-color: transparent;
		background-color: var(--color-surface-elevated);
	}

	.trade-header-left-item p {
		transition: color var(--transition-base);
	}

	.trade-header-left-item:not(.active):hover {
		background-color: var(--color-menu-hover);
	}

	.trade-header-left-item:not(.active):hover p,
	.trade-header-left-item.active p {
		color: var(--color-text);
	}

	/* Vertical separator placed after each tab. Painted only when adjacent
	   to the active tab. The permanent `border-bottom` keeps the horizontal
	   line continuous across the divider's column even when its body is
	   transparent. */
	.divider {
		flex-shrink: 0;
		box-sizing: border-box;
		width: 1px;
		height: 100%;
		background-color: transparent;
		border-bottom: 1px solid var(--color-border);
		transition: background-color var(--transition-base);
	}

	.trade-header-left-item.active + .divider,
	.divider:has(+ .trade-header-left-item.active) {
		background-color: var(--color-border);
	}

	.trade-header-right {
		flex: 1;
		height: 100%;
		display: flex;
		flex-direction: row;
		align-items: center;
		justify-content: flex-end;
		gap: 10px;
		padding: 0 20px;
		border-bottom: 1px solid var(--color-border);
	}

	.settings-icon-container {
		width: 30px;
		height: 30px;
		border-radius: 5px;
		display: flex;
		align-items: center;
		justify-content: center;
		border: 1px solid transparent;
		cursor: pointer;
		transition: all var(--transition-base);
	}

	.settings-icon-container:hover {
		background-color: var(--color-menu-hover);
	}

	.settings-icon-container:active {
		opacity: 0.8;
	}

	.settings-icon {
		width: 18px;
		height: 18px;
		opacity: 0.5;
		transition: all var(--transition-base);
	}

	/* ---------- Body ---------- */
	.trade-body {
		width: 100%;
		flex: 1;
		min-height: 0;
		display: flex;
		flex-direction: column;
		align-items: stretch;
		justify-content: flex-start;
	}

	.trade-advanced {
		width: 100%;
		flex: 1;
		min-height: 0;
		display: flex;
		flex-direction: column;
		align-items: stretch;
		justify-content: flex-start;
	}

	.input-output {
		width: 100%;
		flex: 1;
		min-height: 0;
		display: flex;
		flex-direction: column;
		align-items: stretch;
		justify-content: flex-start;
		padding-top: 20px;
	}

	.input-output-separator {
		position: relative;
		flex-shrink: 0;
		width: 100%;
		height: 1px;
		background-color: var(--color-border);
	}

	.swap-icon {
		all: unset;
		position: absolute;
		left: 50%;
		top: 50%;
		z-index: 1;
		transform: translate(-50%, -50%);
		box-sizing: border-box;
		min-width: 40px;
		height: 30px;
		display: flex;
		align-items: center;
		justify-content: center;
		border: 1px solid var(--color-border);
		border-radius: 5px;
		background-color: var(--color-surface-elevated);
		color: var(--color-text-muted);
		cursor: pointer;
		transition: all var(--transition-base);
	}

	.swap-icon:hover {
		background-color: var(--color-surface);
		color: var(--color-text);
	}

	.swap-icon:active {
		background-color: var(--color-surface-muted);
	}

	.swap-icon-button {
		width: 14px;
		height: 14px;
		display: block;
		transition: transform var(--transition-base);
	}

	/* ---------- Input / Output sections ---------- */
	.info,
	.asset-selector {
		display: flex;
		flex-direction: row;
		align-items: center;
		justify-content: space-between;
		padding: 0 20px 10px;
	}

	.info-right {
		display: flex;
		flex-direction: row;
		align-items: baseline;
		gap: 4px;
		transition: opacity var(--transition-base);
	}

	.info-ticker {
		text-transform: none;
	}

	.info-number {
		margin: 0;
		font-size: var(--text-sm);
		font-weight: 400;
		color: var(--color-text-muted);
		line-height: 1;
		transition: all var(--transition-base);
	}

	/* Sell-side balance is interactive (future: click to MAX-fill).
	   Brighten the number on hover and dim the row on press. */
	.input-output.input .info-right {
		cursor: pointer;
	}

	.input-output.input .info-right:hover .info-number {
		color: var(--color-text);
	}

	.input-output.input .info-right:active .info-number {
		color: var(--color-text-muted);
	}

	.asset-selector-right {
		flex: 1;
		display: flex;
		flex-direction: row;
		align-items: center;
		justify-content: flex-end;
		gap: 5px;
	}

	/* Dropdown's interaction signature is the progressive chevron dip:
	   idle → 0px, hover → 1px, active → 2px, brightening through
	   text-faded → text-muted → text. The downward motion previews the
	   "opens downward" semantic without committing to the 180° rotation
	   that means "menu is open" in established UI grammar.

	   Hover lifts the bg + outer border + inner image border together so
	   the whole control reads as one cohesive surface rather than a
	   bordered button with an image inside it. Press darkens the bg one
	   step below resting (elevated → surface) and snaps via 80ms — at
	   30px tall a transform would feel like a glitch, so all the press
	   feedback is colour-driven. */
	.asset-dropdown {
		all: unset;
		box-sizing: border-box;
		height: 30px;
		display: flex;
		flex-direction: row;
		align-items: center;
		gap: 5px;
		padding: 5px;
		border: 1px solid var(--color-border);
		border-radius: 5px;
		background-color: var(--color-surface-elevated);
		cursor: pointer;
		transition: all var(--transition-base);
	}

	.asset-dropdown:hover {
		background-color: var(--color-surface-muted);
		border-color: var(--color-border-strong);
	}

	.asset-dropdown:active {
		background-color: var(--color-surface);
	}

	.asset-dropdown-left-image {
		width: 20px;
		height: 20px;
		border-radius: 5px;
		border: 1px solid var(--color-border);
		transition: border-color var(--transition-fast);
	}

	.asset-dropdown:hover .asset-dropdown-left-image {
		border-color: var(--color-border-strong);
	}

	.asset-dropdown-name {
		font-size: 12px;
		color: var(--color-text);
		line-height: 1;
	}

	.asset-dropdown-icon {
		margin-left: 5px;
		font-size: 11px;
		color: var(--color-text-faded);
		line-height: 1.1;
		margin-top: 1px;
		transition:
			color var(--transition-fast),
			transform var(--transition-fast);
	}

	.asset-dropdown:hover .asset-dropdown-icon {
		color: var(--color-text-muted);
	}

	.asset-dropdown:active .asset-dropdown-icon {
		color: var(--color-text);
	}

	.asset-selector-right-item {
		all: unset;
		box-sizing: border-box;
		height: 30px;
		display: flex;
		flex-direction: row;
		align-items: center;
		justify-content: center;
		padding: 0 10px;
		border: 1px solid var(--color-border);
		border-radius: 5px;
		background-color: var(--color-surface-elevated);
		opacity: 0.7;
		cursor: pointer;
		transition: all var(--transition-base);
	}

	.asset-selector-right-item:hover {
		opacity: 1;
		border-color: var(--color-border);
	}

	.asset-selector-right-item:active {
		opacity: 0.8;
		background-color: var(--color-surface-muted);
		border-color: var(--color-border);
	}

	.asset-selector-right-item-label {
		font-size: 12px;
		color: var(--color-text);
	}

	.amount-selector {
		flex: 1;
		display: flex;
		flex-direction: column;
		align-items: stretch;
		justify-content: flex-start;
		padding: 30px 20px 10px;
	}

	.amount-input {
		all: unset;
		box-sizing: border-box;
		width: 100%;
		font-size: 28px;
		line-height: 1.2;
		color: var(--color-text);
	}

	.amount-input::placeholder {
		color: var(--color-text-faded);
	}

	/* ---------- Footer ---------- */
	.trade-footer {
		width: 100%;
		height: 100px;
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		gap: 10px;
		padding: 0 20px;
	}

	.swap-button {
		all: unset;
		box-sizing: border-box;
		width: 100%;
		height: 40px;
		padding: 0 20px;
		display: flex;
		align-items: center;
		justify-content: center;
		border-radius: 5px;
		background: linear-gradient(
			to left,
			var(--color-primary-light) -20%,
			var(--color-primary) 100%
		);
		color: var(--color-text-inverse);
		font-size: var(--text-sm);
		font-weight: 400;
		letter-spacing: 1px;
		cursor: pointer;
		transition: all var(--transition-base);
	}

	.swap-button:hover {
		filter: brightness(1.08);
		box-shadow: 0 0 16px -4px color-mix(in oklab, var(--color-primary-light) 40%, transparent);
	}

	.swap-button:active {
		filter: brightness(0.97);
		box-shadow: none;
		transition-duration: 80ms;
	}

	.swap-info {
		box-sizing: border-box;
		width: 100%;
		height: 30px;
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		padding: 0 20px;
		margin-bottom: 10px;
		border-radius: 5px;
		background-color: #202020;
	}
</style>
