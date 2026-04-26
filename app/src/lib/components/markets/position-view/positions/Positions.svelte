<script lang="ts">
	import Loader from '../loader/Loader.svelte';

	type PositionFilter = 'all' | 'profitable' | 'losing';

	type PositionRow = {
		image: string;
		alt: string;
		symbol: string;
		name: string;
		club: string;
		positionTag: string;
		size: number;
		avgEntry: number;
		mark: number;
		pbrEarned: number;
	};

	const filters: { id: PositionFilter; label: string }[] = [
		{ id: 'all', label: 'All' },
		{ id: 'profitable', label: 'Profitable' },
		{ id: 'losing', label: 'Losing' }
	];

	// Wireframe-only seed data. Replace with the user's open spot holdings + cost
	// basis once the indexer (positions table) and on-chain balances are wired.
	// Base assets (ETH/USDC/tGBP/sETH) intentionally excluded — those belong in
	// Balances, since they don't carry a PBR yield stream or a meaningful entry
	// price relative to GBP.
	const rows: PositionRow[] = [
		{
			image: '/tokens/playerToken.svg',
			alt: 'dRICE',
			symbol: 'dRICE',
			name: 'Declan Rice',
			club: 'ARS',
			positionTag: 'd-Midfield',
			size: 1240,
			avgEntry: 1.42,
			mark: 1.61,
			pbrEarned: 84.6
		},
		{
			image: '/tokens/playerToken.svg',
			alt: 'eHAAL',
			symbol: 'eHAAL',
			name: 'Erling Haaland',
			club: 'MCI',
			positionTag: 'Forward',
			size: 312,
			avgEntry: 8.2,
			mark: 9.014,
			pbrEarned: 198.4
		},
		{
			image: '/tokens/playerToken.svg',
			alt: 'bSAKA',
			symbol: 'bSAKA',
			name: 'Bukayo Saka',
			club: 'ARS',
			positionTag: 'Winger',
			size: 540,
			avgEntry: 2.05,
			mark: 1.93,
			pbrEarned: 41.8
		},
		{
			image: '/tokens/playerToken.svg',
			alt: 'mSALA',
			symbol: 'mSALA',
			name: 'Mohamed Salah',
			club: 'LIV',
			positionTag: 'Winger',
			size: 12,
			avgEntry: 3.5,
			mark: 3.2,
			pbrEarned: 0.9
		},
		{
			image: '/tokens/playerToken.svg',
			alt: 'bFERN',
			symbol: 'bFERN',
			name: 'Bruno Fernandes',
			club: 'MUN',
			positionTag: 'a-Midfield',
			size: 49,
			avgEntry: 1.18,
			mark: 1.253,
			pbrEarned: 3.1
		}
	];

	let query = $state('');
	let filter = $state<PositionFilter>('all');

	const LOADING_DURATION_MS = 1200;
	let isLoading = $state(true);

	$effect(() => {
		const timeoutId = setTimeout(() => {
			isLoading = false;
		}, LOADING_DURATION_MS);
		return () => clearTimeout(timeoutId);
	});

	function pnlAbs(row: PositionRow): number {
		return (row.mark - row.avgEntry) * row.size;
	}

	function pnlPct(row: PositionRow): number {
		if (row.avgEntry === 0) return 0;
		return ((row.mark - row.avgEntry) / row.avgEntry) * 100;
	}

	function value(row: PositionRow): number {
		return row.mark * row.size;
	}

	const filtered = $derived(
		rows.filter((row) => {
			const pnl = pnlAbs(row);
			if (filter === 'profitable' && pnl <= 0) return false;
			if (filter === 'losing' && pnl >= 0) return false;
			if (query.trim().length > 0) {
				const q = query.trim().toLowerCase();
				return (
					row.symbol.toLowerCase().includes(q) ||
					row.name.toLowerCase().includes(q) ||
					row.club.toLowerCase().includes(q)
				);
			}
			return true;
		})
	);

	const totalValue = $derived(
		filtered.reduce((sum, row) => sum + value(row), 0)
	);

	const netPnl = $derived(
		filtered.reduce((sum, row) => sum + pnlAbs(row), 0)
	);

	function formatAmount(v: number): string {
		// Trim to 4 decimals and strip trailing zeros so balances feel native to
		// each asset's precision rather than padded to a fixed scale.
		if (v === 0) return '0';
		const fixed = v.toFixed(4);
		return fixed.replace(/\.?0+$/, '');
	}

	function formatGbp(v: number): string {
		return v.toLocaleString('en-GB', {
			minimumFractionDigits: 2,
			maximumFractionDigits: 2
		});
	}

	function formatSignedGbp(v: number): string {
		const sign = v > 0 ? '+' : v < 0 ? '−' : '';
		return `${sign}£ ${formatGbp(Math.abs(v))}`;
	}

	function formatSignedPct(v: number): string {
		const sign = v > 0 ? '+' : v < 0 ? '−' : '';
		return `${sign}${Math.abs(v).toFixed(2)}%`;
	}
</script>

<div class="positions">
	<div class="positions-toolbar">
		<div class="positions-toolbar-left">
			<div class="search">
				<i class="fa-solid fa-magnifying-glass search-icon" aria-hidden="true"></i>
				<input
					type="text"
					class="search-input"
					placeholder="Search position"
					autocomplete="off"
					spellcheck="false"
					aria-label="Search positions"
					bind:value={query}
				/>
			</div>
			<div class="filter-segments" role="tablist" aria-label="Position filter">
				{#each filters as f (f.id)}
					<button
						type="button"
						class="filter-segment"
						class:filter-segment--active={filter === f.id}
						role="tab"
						aria-selected={filter === f.id}
						onclick={() => (filter = f.id)}
					>
						{f.label}
					</button>
				{/each}
			</div>
		</div>
		<div class="positions-toolbar-right">
			<div class="summary">
				<span class="summary-label">Net PnL</span>
				<span
					class="summary-value"
					class:summary-value--positive={netPnl > 0}
					class:summary-value--negative={netPnl < 0}
				>
					{formatSignedGbp(netPnl)}
				</span>
			</div>
			<div class="summary summary--bordered">
				<span class="summary-label">Total Value</span>
				<span class="summary-value">£ {formatGbp(totalValue)}</span>
			</div>
		</div>
	</div>

	<div class="positions-grid" role="grid" aria-rowcount={filtered.length + 1}>
		<div class="positions-row positions-row--head" role="row">
			<div class="cell cell--asset" role="columnheader">Asset</div>
			<div class="cell cell--num" role="columnheader">Size</div>
			<div class="cell cell--num" role="columnheader">Avg Entry</div>
			<div class="cell cell--num" role="columnheader">Mark</div>
			<div class="cell cell--num" role="columnheader">PnL</div>
			<div class="cell cell--num" role="columnheader">PBR Earned</div>
			<div class="cell cell--num" role="columnheader">Value (GBP)</div>
			<div class="cell cell--actions" role="columnheader" aria-label="Actions"></div>
		</div>

		<div class="positions-body">
			{#each filtered as row (row.symbol)}
				{@const pAbs = pnlAbs(row)}
				{@const pPct = pnlPct(row)}
				{@const positive = pAbs > 0}
				{@const negative = pAbs < 0}
				<div class="positions-row" role="row">
					<div class="cell cell--asset" role="gridcell">
						<img src={row.image} alt={row.alt} class="asset-image" />
						<div class="asset-text">
							<span class="asset-symbol">{row.symbol}</span>
							<span class="asset-name">{row.name}</span>
						</div>
					</div>
					<div class="cell cell--num" role="gridcell">{formatAmount(row.size)}</div>
					<div class="cell cell--num" role="gridcell">£ {formatGbp(row.avgEntry)}</div>
					<div class="cell cell--num" role="gridcell">£ {formatGbp(row.mark)}</div>
					<div
						class="cell cell--num cell--pnl"
						class:cell--positive={positive}
						class:cell--negative={negative}
						role="gridcell"
					>
						<span class="pnl-abs">{formatSignedGbp(pAbs)}</span>
						<span class="pnl-pct">{formatSignedPct(pPct)}</span>
					</div>
					<div
						class="cell cell--num"
						class:cell--muted={row.pbrEarned === 0}
						class:cell--positive={row.pbrEarned > 0}
						role="gridcell"
					>
						£ {formatGbp(row.pbrEarned)}
					</div>
					<div class="cell cell--num cell--value" role="gridcell">
						£ {formatGbp(value(row))}
					</div>
					<div class="cell cell--actions" role="gridcell">
						<button type="button" class="row-action">Trade</button>
						<button type="button" class="row-action row-action--danger">Close</button>
					</div>
				</div>
			{:else}
				<div class="empty">
					<p class="empty-text">No positions match the current filters.</p>
				</div>
			{/each}
			<Loader visible={isLoading} label="Loading positions" />
		</div>
	</div>
</div>

<style>
	.positions {
		flex: 1 1 auto;
		min-height: 0;
		display: flex;
		flex-direction: column;
		align-items: stretch;
	}

	.positions-toolbar {
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

	.positions-toolbar-left,
	.positions-toolbar-right {
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

	.summary {
		display: flex;
		flex-direction: row;
		align-items: baseline;
		gap: 8px;
	}

	.summary--bordered {
		padding-left: 15px;
		border-left: 1px solid var(--color-border-light);
	}

	.summary-label {
		font-size: var(--text-xs);
		color: var(--color-text-muted);
		letter-spacing: var(--tracking-default);
	}

	.summary-value {
		font-size: var(--text-sm);
		color: var(--color-text);
		letter-spacing: var(--tracking-default);
		font-variant-numeric: tabular-nums;
	}

	.summary-value--positive {
		color: var(--color-success);
	}

	.summary-value--negative {
		color: var(--color-error);
	}

	.positions-grid {
		flex: 1 1 auto;
		min-height: 0;
		display: flex;
		flex-direction: column;
		align-items: stretch;
	}

	.positions-row {
		display: grid;
		grid-template-columns:
			minmax(180px, 2fr)
			minmax(90px, 1fr)
			minmax(110px, 1fr)
			minmax(110px, 1fr)
			minmax(140px, 1.2fr)
			minmax(120px, 1fr)
			minmax(130px, 1fr)
			minmax(140px, auto);
		align-items: center;
		gap: 20px;
		padding: 0 20px;
		height: 48px;
		border-bottom: 1px solid var(--color-border-light);
		transition: background-color var(--transition-base);
	}

	.positions-row--head {
		flex-shrink: 0;
		height: 32px;
		background-color: var(--color-surface-elevated);
	}

	.positions-body {
		position: relative;
		flex: 1 1 auto;
		min-height: 0;
		overflow-y: auto;
	}

	.positions-body::-webkit-scrollbar {
		width: 0;
	}

	.positions-body::-webkit-scrollbar-track {
		background: transparent;
		border-radius: 0;
	}

	.positions-body::-webkit-scrollbar-thumb {
		background: var(--color-border-strong);
		border-radius: 1px;
	}

	.positions-body .positions-row:hover {
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

	.positions-row--head .cell {
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

	.asset-name-sep {
		color: var(--color-text-faded);
		margin: 0 5px;
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

	.cell--positive {
		color: var(--color-success);
	}

	.cell--negative {
		color: var(--color-error);
	}

	.cell--pnl {
		display: flex;
		flex-direction: column;
		align-items: flex-end;
		gap: 2px;
		justify-content: center;
	}

	.pnl-abs {
		font-size: var(--text-sm);
		line-height: 1;
	}

	.pnl-pct {
		font-size: var(--text-xs);
		line-height: 1;
		opacity: 0.85;
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

	.row-action--danger {
		color: var(--color-text-muted);
	}

	.row-action--danger:hover {
		color: var(--color-error);
		border-color: var(--color-error);
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
