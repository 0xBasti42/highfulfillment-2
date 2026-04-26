<script lang="ts">
	import Loader from '../loader/Loader.svelte';

	type AssetClass = 'all' | 'players' | 'base';

	type BalanceRow = {
		image: string;
		alt: string;
		symbol: string;
		name: string;
		assetClass: Exclude<AssetClass, 'all'>;
		total: number;
		available: number;
		locked: number;
		valueGbp: number;
	};

	const filters: { id: AssetClass; label: string }[] = [
		{ id: 'all', label: 'All' },
		{ id: 'players', label: 'Player Tokens' },
		{ id: 'base', label: 'Base Assets' }
	];

	// Wireframe-only seed data. Replace with the user's Smart Account balances
	// once the CDP read pipeline is wired into a store.
	const rows: BalanceRow[] = [
		{
			image: '/tokens/eth.svg',
			alt: 'ETH',
			symbol: 'ETH',
			name: 'Ethereum',
			assetClass: 'base',
			total: 0.4321,
			available: 0.4321,
			locked: 0,
			valueGbp: 1287.45
		},
		{
			image: '/tokens/seth-dec-3.svg',
			alt: 'sETH',
			symbol: 'sETH',
			name: 'Stability ETH',
			assetClass: 'base',
			total: 0.812,
			available: 0.812,
			locked: 0,
			valueGbp: 2418.7
		},
		{
			image: '/tokens/usdc.svg',
			alt: 'USDC',
			symbol: 'USDC',
			name: 'USD Coin',
			assetClass: 'base',
			total: 482.91,
			available: 482.91,
			locked: 0,
			valueGbp: 380.65
		},
		{
			image: '/tokens/tgbp-blue.svg',
			alt: 'tGBP',
			symbol: 'tGBP',
			name: 'Tokenised GBP',
			assetClass: 'base',
			total: 1240.0,
			available: 1100.0,
			locked: 140.0,
			valueGbp: 1240.0
		},
		{
			image: '/tokens/playerToken.svg',
			alt: 'dRICE',
			symbol: 'dRICE',
			name: 'Declan Rice',
			assetClass: 'players',
			total: 1240,
			available: 980,
			locked: 260,
			valueGbp: 1996.4
		},
		{
			image: '/tokens/playerToken.svg',
			alt: 'eHAAL',
			symbol: 'eHAAL',
			name: 'Erling Haaland',
			assetClass: 'players',
			total: 312,
			available: 312,
			locked: 0,
			valueGbp: 2812.32
		},
		{
			image: '/tokens/playerToken.svg',
			alt: 'bSAKA',
			symbol: 'bSAKA',
			name: 'Bukayo Saka',
			assetClass: 'players',
			total: 540,
			available: 400,
			locked: 140,
			valueGbp: 1042.2
		},
		{
			image: '/tokens/playerToken.svg',
			alt: 'mSALA',
			symbol: 'mSALA',
			name: 'Mohamed Salah',
			assetClass: 'players',
			total: 12,
			available: 12,
			locked: 0,
			valueGbp: 38.4
		},
		{
			image: '/tokens/playerToken.svg',
			alt: 'bFERN',
			symbol: 'bFERN',
			name: 'Bruno Fernandes',
			assetClass: 'players',
			total: 49,
			available: 49,
			locked: 0,
			valueGbp: 61.4
		}
	];

	let query = $state('');
	let hideSmall = $state(false);
	let assetClass = $state<AssetClass>('all');

	const SMALL_BALANCE_GBP = 10;

	// Brief loading overlay on initial mount (and on every re-mount when the
	// user navigates away and back via PositionView's `{#if activeTab === ...}`).
	// Fixed duration matches Chart.svelte's mount-cover pattern.
	const LOADING_DURATION_MS = 1200;
	let isLoading = $state(true);

	$effect(() => {
		const timeoutId = setTimeout(() => {
			isLoading = false;
		}, LOADING_DURATION_MS);
		return () => clearTimeout(timeoutId);
	});

	const filtered = $derived(
		rows.filter((row) => {
			if (assetClass !== 'all' && row.assetClass !== assetClass) return false;
			if (hideSmall && row.valueGbp < SMALL_BALANCE_GBP) return false;
			if (query.trim().length > 0) {
				const q = query.trim().toLowerCase();
				return (
					row.symbol.toLowerCase().includes(q) || row.name.toLowerCase().includes(q)
				);
			}
			return true;
		})
	);

	const totalValue = $derived(
		filtered.reduce((sum, row) => sum + row.valueGbp, 0)
	);

	function formatAmount(value: number): string {
		// Trim to 4 decimals and strip trailing zeros so balances feel native to
		// each asset's precision rather than padded to a fixed scale.
		if (value === 0) return '0';
		const fixed = value.toFixed(4);
		return fixed.replace(/\.?0+$/, '');
	}

	function formatGbp(value: number): string {
		return value.toLocaleString('en-GB', {
			minimumFractionDigits: 2,
			maximumFractionDigits: 2
		});
	}
</script>

<div class="balances">
	<div class="balances-toolbar">
		<div class="balances-toolbar-left">
			<div class="search">
				<i class="fa-solid fa-magnifying-glass search-icon" aria-hidden="true"></i>
				<input
					type="text"
					class="search-input"
					placeholder="Search asset"
					autocomplete="off"
					spellcheck="false"
					aria-label="Search balances"
					bind:value={query}
				/>
			</div>
			<div class="filter-segments" role="tablist" aria-label="Asset class filter">
				{#each filters as f (f.id)}
					<button
						type="button"
						class="filter-segment"
						class:filter-segment--active={assetClass === f.id}
						role="tab"
						aria-selected={assetClass === f.id}
						onclick={() => (assetClass = f.id)}
					>
						{f.label}
					</button>
				{/each}
			</div>
		</div>
		<div class="balances-toolbar-right">
			<label class="toggle">
				<input type="checkbox" bind:checked={hideSmall} />
				<span style="font-size: 10px;">Hide small balances</span>
			</label>
			<div class="total">
				<span class="total-label">Total</span>
				<span class="total-value">£ {formatGbp(totalValue)}</span>
			</div>
		</div>
	</div>

	<div class="balances-grid" role="grid" aria-rowcount={filtered.length + 1}>
		<div class="balances-row balances-row--head" role="row">
			<div class="cell cell--asset" role="columnheader">Asset</div>
			<div class="cell cell--num" role="columnheader">Total</div>
			<div class="cell cell--num" role="columnheader">Available</div>
			<div class="cell cell--num" role="columnheader">Locked</div>
			<div class="cell cell--num" role="columnheader">Value (GBP)</div>
			<div class="cell cell--actions" role="columnheader" aria-label="Actions"></div>
		</div>

		<div class="balances-body">
			{#each filtered as row (row.symbol)}
				<div class="balances-row" role="row">
					<div class="cell cell--asset" role="gridcell">
						<img src={row.image} alt={row.alt} class="asset-image" />
						<div class="asset-text">
							<span class="asset-symbol">{row.symbol}</span>
							<span class="asset-name">{row.name}</span>
						</div>
					</div>
					<div class="cell cell--num" role="gridcell">{formatAmount(row.total)}</div>
					<div class="cell cell--num" role="gridcell">{formatAmount(row.available)}</div>
					<div
						class="cell cell--num"
						class:cell--muted={row.locked === 0}
						role="gridcell"
					>
						{formatAmount(row.locked)}
					</div>
					<div class="cell cell--num cell--value" role="gridcell">
						£ {formatGbp(row.valueGbp)}
					</div>
					<div class="cell cell--actions" role="gridcell">
						<button type="button" class="row-action">Trade</button>
						<button
							type="button"
							class="row-action row-action--ghost"
							aria-label="Deposit {row.symbol}"
						>
							<i class="fa-solid fa-arrow-down" aria-hidden="true"></i>
						</button>
						<button
							type="button"
							class="row-action row-action--ghost"
							aria-label="Withdraw {row.symbol}"
						>
							<i class="fa-solid fa-arrow-up" aria-hidden="true"></i>
						</button>
					</div>
				</div>
			{:else}
				<div class="empty">
					<p class="empty-text">No balances match the current filters.</p>
				</div>
			{/each}
			<Loader visible={isLoading} label="Loading balances" />
		</div>
	</div>
</div>

<style>
	.balances {
		flex: 1 1 auto;
		min-height: 0;
		display: flex;
		flex-direction: column;
		align-items: stretch;
	}

	.balances-toolbar {
		flex-shrink: 0;
		height: 44px;
		display: flex;
		flex-direction: row;
		align-items: center;
		justify-content: space-between;
		gap: 20px;
		padding: 0 20px;
		border-bottom: 1px solid var(--color-border-light);
	}

	.balances-toolbar-left,
	.balances-toolbar-right {
		display: flex;
		flex-direction: row;
		align-items: center;
		gap: 15px;
	}

	.search {
		display: flex;
		flex-direction: row;
		align-items: center;
		gap: 8px;
		height: 26px;
		padding: 0 10px;
		background-color: var(--color-surface-elevated);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-sm);
		transition: border-color var(--transition-base);
	}

	.search:focus-within {
		border-color: var(--color-border-strong);
	}

	.search-icon {
		font-size: 10px;
		color: var(--color-text-faded);
	}

	.search-input {
		all: unset;
		box-sizing: border-box;
		width: 140px;
		font-size: var(--text-sm);
		color: var(--color-text);
		letter-spacing: var(--tracking-default);
	}

	.filter-segments {
		display: flex;
		flex-direction: row;
		align-items: center;
		gap: 0;
		background-color: var(--color-surface-elevated);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-sm);
		padding: 2px;
	}

	.filter-segment {
		all: unset;
		box-sizing: border-box;
		min-width: 0;
		height: 22px;
		padding: 0 10px;
		display: flex;
		align-items: center;
		justify-content: center;
		font-size: var(--text-xs);
		letter-spacing: var(--tracking-default);
		color: var(--color-text-muted);
		cursor: pointer;
		border-radius: 3px;
		transition:
			color var(--transition-base),
			background-color var(--transition-base);
	}

	.filter-segment:hover {
		color: var(--color-text);
	}

	.filter-segment--active {
		color: var(--color-text);
		background-color: var(--color-surface-muted);
	}

	.toggle {
		display: flex;
		align-items: center;
		gap: 8px;
		font-size: var(--text-sm);
		color: var(--color-text-muted);
		letter-spacing: var(--tracking-default);
		cursor: pointer;
		transition: all var(--transition-base);
	}

	.total {
		display: flex;
		flex-direction: row;
		align-items: baseline;
		gap: 8px;
		padding-left: 15px;
		border-left: 1px solid var(--color-border);
        height: 40%;
	}

	.total-label {
		font-size: var(--text-xs);
		color: var(--color-text-muted);
		letter-spacing: var(--tracking-default);
	}

	.total-value {
		font-size: var(--text-sm);
		color: var(--color-text);
		letter-spacing: var(--tracking-default);
	}

	.balances-grid {
		flex: 1 1 auto;
		min-height: 0;
		display: flex;
		flex-direction: column;
		align-items: stretch;
	}

	.balances-row {
		display: grid;
		grid-template-columns:
			minmax(180px, 2fr)
			minmax(110px, 1fr)
			minmax(110px, 1fr)
			minmax(110px, 1fr)
			minmax(130px, 1fr)
			minmax(140px, auto);
		align-items: center;
		gap: 20px;
		padding: 0 20px;
		height: 48px;
		border-bottom: 1px solid var(--color-border-light);
		transition: background-color var(--transition-base);
	}

	.balances-row--head {
		flex-shrink: 0;
		height: 32px;
		background-color: var(--color-surface-elevated);
	}

	.balances-body {
		position: relative;
		flex: 1 1 auto;
		min-height: 0;
		overflow-y: auto;
	}

	.balances-body::-webkit-scrollbar {
		width: 0;
	}

	.balances-body::-webkit-scrollbar-track {
		background: transparent;
		border-radius: 0;
	}

	.balances-body::-webkit-scrollbar-thumb {
		background: var(--color-border-strong);
		border-radius: 1px;
	}

	.balances-body .balances-row:hover {
		background-color: var(--color-surface-elevated);
	}

	.cell {
		font-size: var(--text-sm);
		font-weight: 400;
		letter-spacing: var(--tracking-default);
		color: var(--color-text);
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}

	.balances-row--head .cell {
		font-size: var(--text-xs);
		color: var(--color-text-muted);
		text-transform: uppercase;
	}

	.cell--asset {
		display: flex;
		flex-direction: row;
		align-items: center;
		gap: 10px;
		min-width: 0;
	}

	.asset-image {
		width: 24px;
		height: 24px;
		flex-shrink: 0;
		object-fit: cover;
		border-radius: 4px;
		background: linear-gradient(to bottom, #202020 -20%, #151515 100%);
		border: 1px solid var(--color-border);
	}

	.asset-text {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		gap: 2px;
		min-width: 0;
	}

	.asset-symbol {
		font-size: var(--text-sm);
		color: var(--color-text);
		line-height: 1;
	}

	.asset-name {
		font-size: var(--text-xs);
		color: var(--color-text-muted);
		line-height: 1.3;
		max-width: 100%;
		overflow: hidden;
		text-overflow: ellipsis;
	}

	.cell--num {
		text-align: right;
		justify-self: end;
		font-variant-numeric: tabular-nums;
	}

	.cell--value {
		color: var(--color-text);
	}

	.cell--muted {
		color: var(--color-text-faded);
	}

	.cell--actions {
		display: flex;
		flex-direction: row;
		align-items: center;
		justify-content: flex-end;
		gap: 6px;
		justify-self: end;
	}

	.row-action {
		all: unset;
		box-sizing: border-box;
		min-width: 0;
		height: 24px;
		padding: 0 12px;
		display: inline-flex;
		align-items: center;
		justify-content: center;
		font-size: var(--text-xs);
		letter-spacing: var(--tracking-default);
		color: var(--color-text);
		background-color: var(--color-surface-elevated);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-sm);
		cursor: pointer;
		transition:
			background-color var(--transition-base),
			border-color var(--transition-base),
			color var(--transition-base);
	}

	.row-action:hover {
		background-color: var(--color-surface-muted);
		border-color: var(--color-border-strong);
	}

	.row-action:active {
		opacity: 0.8;
	}

	.row-action--ghost {
		width: 24px;
		padding: 0;
		color: var(--color-text-muted);
	}

	.row-action--ghost:hover {
		color: var(--color-text);
	}

	.empty {
		display: flex;
		align-items: center;
		justify-content: center;
		padding: 30px 20px;
	}

	.empty-text {
		margin: 0;
		font-size: var(--text-sm);
		color: var(--color-text-muted);
		letter-spacing: var(--tracking-default);
	}
</style>
