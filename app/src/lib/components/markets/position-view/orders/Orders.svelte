<script lang="ts">
	import Loader from '../loader/Loader.svelte';

	type OrderFilter = 'all' | 'buy' | 'sell';
	type OrderType = 'limit' | 'stop';
	type OrderSide = 'buy' | 'sell';

	type OrderRow = {
		image: string;
		alt: string;
		symbol: string;
		name: string;
		club: string;
		type: OrderType;
		side: OrderSide;
		priceGbp: number;
		size: number;
		filled: number;
		// Unix-ms timestamp the order was placed; used to render a relative
		// "Xm/h/d ago" string with `formatRelative` below.
		placedAt: number;
	};

	const filters: { id: OrderFilter; label: string }[] = [
		{ id: 'all', label: 'All' },
		{ id: 'buy', label: 'Buy' },
		{ id: 'sell', label: 'Sell' }
	];

	// Wireframe-only seed data. Replace with the user's open orders once a
	// venue (v4 limit-order hook or off-chain book) is selected and indexed.
	// `placedAt` is computed at module load so the relative timestamps stay
	// stable across re-renders within a session.
	const NOW = Date.now();
	const MIN = 60_000;
	const HOUR = 60 * MIN;
	const DAY = 24 * HOUR;

	const rows: OrderRow[] = [
		{
			image: '/tokens/playerToken.svg',
			alt: 'dRICE',
			symbol: 'dRICE',
			name: 'Declan Rice',
			club: 'ARS',
			type: 'limit',
			side: 'buy',
			priceGbp: 1.55,
			size: 500,
			filled: 0,
			placedAt: NOW - 4 * MIN
		},
		{
			image: '/tokens/playerToken.svg',
			alt: 'eHAAL',
			symbol: 'eHAAL',
			name: 'Erling Haaland',
			club: 'MCI',
			type: 'limit',
			side: 'sell',
			priceGbp: 9.5,
			size: 80,
			filled: 32,
			placedAt: NOW - 22 * MIN
		},
		{
			image: '/tokens/playerToken.svg',
			alt: 'bSAKA',
			symbol: 'bSAKA',
			name: 'Bukayo Saka',
			club: 'ARS',
			type: 'stop',
			side: 'sell',
			priceGbp: 1.75,
			size: 540,
			filled: 0,
			placedAt: NOW - 3 * HOUR
		},
		{
			image: '/tokens/playerToken.svg',
			alt: 'mSALA',
			symbol: 'mSALA',
			name: 'Mohamed Salah',
			club: 'LIV',
			type: 'limit',
			side: 'buy',
			priceGbp: 3.0,
			size: 120,
			filled: 60,
			placedAt: NOW - 9 * HOUR
		},
		{
			image: '/tokens/playerToken.svg',
			alt: 'bFERN',
			symbol: 'bFERN',
			name: 'Bruno Fernandes',
			club: 'MUN',
			type: 'limit',
			side: 'buy',
			priceGbp: 1.18,
			size: 200,
			filled: 0,
			placedAt: NOW - 2 * DAY
		},
		{
			image: '/tokens/playerToken.svg',
			alt: 'dRICE',
			symbol: 'dRICE',
			name: 'Declan Rice',
			club: 'ARS',
			type: 'stop',
			side: 'sell',
			priceGbp: 1.45,
			size: 1240,
			filled: 0,
			placedAt: NOW - 5 * DAY
		}
	];

	let query = $state('');
	let filter = $state<OrderFilter>('all');

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
			if (filter !== 'all' && row.side !== filter) return false;
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

	function formatAmount(v: number): string {
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

	function formatRelative(placedAt: number): string {
		// Bucketed relative time. Anything 7d+ falls back to a short date so the
		// row doesn't read "60d ago" — once orders get that stale, an absolute
		// date is more useful.
		const diff = Math.max(0, NOW - placedAt);
		if (diff < HOUR) return `${Math.max(1, Math.floor(diff / MIN))}m ago`;
		if (diff < DAY) return `${Math.floor(diff / HOUR)}h ago`;
		if (diff < 7 * DAY) return `${Math.floor(diff / DAY)}d ago`;
		return new Date(placedAt).toLocaleDateString('en-GB', {
			day: '2-digit',
			month: 'short'
		});
	}

	function fillPct(row: OrderRow): number {
		if (row.size === 0) return 0;
		return Math.min(100, (row.filled / row.size) * 100);
	}

	function total(row: OrderRow): number {
		return row.priceGbp * row.size;
	}

	function cancelAll() {
		// Wireframe-only; real impl will call the venue's cancel endpoint /
		// contract method per visible order id.
	}

	function cancel(_row: OrderRow) {
		// Wireframe-only.
	}
</script>

<div class="orders">
	<div class="orders-toolbar">
		<div class="orders-toolbar-left">
			<div class="search">
				<i class="fa-solid fa-magnifying-glass search-icon" aria-hidden="true"></i>
				<input
					type="text"
					class="search-input"
					placeholder="Search order"
					autocomplete="off"
					spellcheck="false"
					aria-label="Search orders"
					bind:value={query}
				/>
			</div>
			<div class="filter-segments" role="tablist" aria-label="Order side filter">
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
		<div class="orders-toolbar-right">
			<div class="summary">
				<span class="summary-label">Open</span>
				<span class="summary-value">{filtered.length}</span>
			</div>
			<button
				type="button"
				class="cancel-all"
				onclick={cancelAll}
				disabled={filtered.length === 0}
			>
				Cancel All
			</button>
		</div>
	</div>

	<div class="orders-grid" role="grid" aria-rowcount={filtered.length + 1}>
		<div class="orders-row orders-row--head" role="row">
			<div class="cell cell--asset" role="columnheader">Asset</div>
			<div class="cell" role="columnheader">Type</div>
			<div class="cell" role="columnheader">Side</div>
			<div class="cell cell--num" role="columnheader">Price</div>
			<div class="cell cell--num" role="columnheader">Size</div>
			<div class="cell cell--num" role="columnheader">Filled</div>
			<div class="cell cell--num" role="columnheader">Total (GBP)</div>
			<div class="cell cell--num" role="columnheader">Time</div>
			<div class="cell cell--actions" role="columnheader" aria-label="Actions"></div>
		</div>

		<div class="orders-body">
			{#each filtered as row, i (i)}
				{@const pct = fillPct(row)}
				{@const isPartial = row.filled > 0}
				<div class="orders-row" role="row">
					<div class="cell cell--asset" role="gridcell">
						<img src={row.image} alt={row.alt} class="asset-image" />
						<div class="asset-text">
							<span class="asset-symbol">{row.symbol}</span>
							<span class="asset-name">{row.name}</span>
						</div>
					</div>
					<div class="cell" role="gridcell">
						<span class="type-tag">{row.type === 'limit' ? 'Limit' : 'Stop'}</span>
					</div>
					<div class="cell" role="gridcell">
						<span
							class="side-pill"
							class:side-pill--buy={row.side === 'buy'}
							class:side-pill--sell={row.side === 'sell'}
						>
							{row.side === 'buy' ? 'Buy' : 'Sell'}
						</span>
					</div>
					<div class="cell cell--num" role="gridcell">£ {formatGbp(row.priceGbp)}</div>
					<div class="cell cell--num" role="gridcell">{formatAmount(row.size)}</div>
					<div class="cell cell--num cell--filled" role="gridcell">
						<span class="filled-text" class:filled-text--partial={isPartial}>
							{formatAmount(row.filled)} / {formatAmount(row.size)}
						</span>
						<span class="filled-bar" aria-hidden="true">
							<span
								class="filled-bar-progress"
								class:filled-bar-progress--buy={row.side === 'buy'}
								class:filled-bar-progress--sell={row.side === 'sell'}
								style:width="{pct}%"
							></span>
						</span>
					</div>
					<div class="cell cell--num cell--value" role="gridcell">
						£ {formatGbp(total(row))}
					</div>
					<div class="cell cell--num cell--time" role="gridcell">
						{formatRelative(row.placedAt)}
					</div>
					<div class="cell cell--actions" role="gridcell">
						<button
							type="button"
							class="row-action row-action--danger"
							onclick={() => cancel(row)}
						>
							Cancel
						</button>
					</div>
				</div>
			{:else}
				<div class="empty">
					<p class="empty-text">No open orders.</p>
				</div>
			{/each}
			<Loader visible={isLoading} label="Loading orders" />
		</div>
	</div>
</div>

<style>
	.orders {
		flex: 1 1 auto;
		min-height: 0;
		display: flex;
		flex-direction: column;
		align-items: stretch;
	}

	.orders-toolbar {
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

	.orders-toolbar-left,
	.orders-toolbar-right {
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

	.cancel-all {
		all: unset;
		box-sizing: border-box;
		min-width: 0;
		height: 26px;
		padding: 0 12px;
		display: inline-flex;
		align-items: center;
		justify-content: center;
		font-size: var(--text-xs);
		letter-spacing: var(--tracking-default);
		color: var(--color-text-muted);
		background-color: var(--color-surface-elevated);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-sm);
		cursor: pointer;
		transition:
			color var(--transition-base),
			background-color var(--transition-base),
			border-color var(--transition-base),
			opacity var(--transition-base);
	}

	.cancel-all:hover:not(:disabled) {
		color: var(--color-error);
		border-color: var(--color-error);
	}

	.cancel-all:active:not(:disabled) {
		opacity: 0.8;
	}

	.cancel-all:disabled {
		cursor: not-allowed;
		opacity: 0.4;
	}

	.orders-grid {
		flex: 1 1 auto;
		min-height: 0;
		display: flex;
		flex-direction: column;
		align-items: stretch;
	}

	.orders-row {
		display: grid;
		grid-template-columns:
			minmax(160px, 1.6fr)
			minmax(70px, 0.7fr)
			minmax(70px, 0.7fr)
			minmax(100px, 1fr)
			minmax(100px, 1fr)
			minmax(140px, 1.3fr)
			minmax(120px, 1fr)
			minmax(80px, 0.8fr)
			minmax(110px, auto);
		align-items: center;
		gap: 20px;
		padding: 0 20px;
		height: 48px;
		border-bottom: 1px solid var(--color-border-light);
		transition: background-color var(--transition-base);
	}

	.orders-row--head {
		flex-shrink: 0;
		height: 32px;
		background-color: var(--color-surface-elevated);
	}

	.orders-body {
		position: relative;
		flex: 1 1 auto;
		min-height: 0;
		overflow-y: auto;
	}

	.orders-body::-webkit-scrollbar {
		width: 0;
	}

	.orders-body::-webkit-scrollbar-track {
		background: transparent;
		border-radius: 0;
	}

	.orders-body::-webkit-scrollbar-thumb {
		background: var(--color-border-strong);
		border-radius: 1px;
	}

	.orders-body .orders-row:hover {
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

	.orders-row--head .cell {
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

	.cell--time {
		color: var(--color-text-muted);
	}

	.type-tag {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		min-height: 20px;
		padding: 0 8px;
		font-size: var(--text-xs);
		letter-spacing: var(--tracking-default);
		color: var(--color-text-muted);
		background-color: var(--color-surface-elevated);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-sm);
	}

	.side-pill {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		min-height: 20px;
		padding: 0 8px;
		font-size: var(--text-xs);
		letter-spacing: var(--tracking-default);
		border: 1px solid transparent;
		border-radius: var(--radius-sm);
	}

	.side-pill--buy {
		color: var(--color-success);
		background-color: color-mix(in oklab, var(--color-success) 12%, transparent);
		border-color: color-mix(in oklab, var(--color-success) 30%, transparent);
	}

	.side-pill--sell {
		color: var(--color-error);
		background-color: color-mix(in oklab, var(--color-error) 12%, transparent);
		border-color: color-mix(in oklab, var(--color-error) 30%, transparent);
	}

	.cell--filled {
		display: flex;
		flex-direction: column;
		align-items: stretch;
		gap: 4px;
		justify-content: center;
		min-width: 0;
	}

	.filled-text {
		text-align: right;
		font-size: var(--text-xs);
		color: var(--color-text-muted);
		font-variant-numeric: tabular-nums;
	}

	.filled-text--partial {
		color: var(--color-text);
	}

	.filled-bar {
		display: block;
		width: 100%;
		height: 2px;
		background-color: var(--color-surface-elevated);
		border-radius: 1px;
		overflow: hidden;
	}

	.filled-bar-progress {
		display: block;
		height: 100%;
		border-radius: 1px;
		transition: width var(--transition-base);
	}

	.filled-bar-progress--buy {
		background-color: var(--color-success);
	}

	.filled-bar-progress--sell {
		background-color: var(--color-error);
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
