<script lang="ts">
	import Loader from '../loader/Loader.svelte';

	type EventFilter = 'all' | 'trades' | 'cancelled' | 'yield';
	type TimeRange = '24h' | '7d' | '30d' | 'all';
	type EventKind = 'buy' | 'sell' | 'cancelled' | 'yield';

	type HistoryRow = {
		image: string;
		alt: string;
		symbol: string;
		name: string;
		club: string;
		event: EventKind;
		// Price per token in GBP. `null` for events where price is meaningless
		// (e.g. yield distributions, plain cancellations without a fill).
		priceGbp: number | null;
		size: number;
		// Total value in GBP. For yield events this is the GBP value of the
		// distribution; for trades it's price * size.
		totalGbp: number;
		feeGbp: number | null;
		// Unix-ms timestamp of the event.
		timestamp: number;
		txHash: string;
	};

	const eventFilters: { id: EventFilter; label: string }[] = [
		{ id: 'all', label: 'All' },
		{ id: 'trades', label: 'Trades' },
		{ id: 'cancelled', label: 'Cancelled' },
		{ id: 'yield', label: 'Yield' }
	];

	const ranges: { id: TimeRange; label: string }[] = [
		{ id: '24h', label: '24h' },
		{ id: '7d', label: '7d' },
		{ id: '30d', label: '30d' },
		{ id: 'all', label: 'All' }
	];

	const NOW = Date.now();
	const MIN = 60_000;
	const HOUR = 60 * MIN;
	const DAY = 24 * HOUR;

	// Wireframe-only seed data. Real implementation will pull from a unified
	// activity-log query: trade fills (indexer), order lifecycle events
	// (venue), and PBR distributions (PBR contract logs), merged by timestamp.
	const rows: HistoryRow[] = [
		{
			image: '/tokens/playerToken.svg',
			alt: 'dRICE',
			symbol: 'dRICE',
			club: 'ARS',
			name: 'Declan Rice',
			event: 'yield',
			priceGbp: null,
			size: 84.6,
			totalGbp: 84.6,
			feeGbp: null,
			timestamp: NOW - 25 * MIN,
			txHash: '0x1f0a9c27b81c4d7e3a6f5b8e2d9c4a7e6f1b3d5c8a4e7b9f2c1a3d5e7b9c1f3a'
		},
		{
			image: '/tokens/playerToken.svg',
			alt: 'eHAAL',
			symbol: 'eHAAL',
			club: 'MCI',
			name: 'Erling Haaland',
			event: 'sell',
			priceGbp: 9.014,
			size: 32,
			totalGbp: 288.45,
			feeGbp: 0.86,
			timestamp: NOW - 2 * HOUR,
			txHash: '0xa3b2c1d0e9f8a7b6c5d4e3f2a1b0c9d8e7f6a5b4c3d2e1f0a9b8c7d6e5f4a3b2'
		},
		{
			image: '/tokens/playerToken.svg',
			alt: 'bSAKA',
			symbol: 'bSAKA',
			club: 'ARS',
			name: 'Bukayo Saka',
			event: 'cancelled',
			priceGbp: 1.85,
			size: 200,
			totalGbp: 370.0,
			feeGbp: null,
			timestamp: NOW - 9 * HOUR,
			txHash: '0xc7d6e5f4a3b2c1d0e9f8a7b6c5d4e3f2a1b0c9d8e7f6a5b4c3d2e1f0a9b8c7d6'
		},
		{
			image: '/tokens/playerToken.svg',
			alt: 'dRICE',
			symbol: 'dRICE',
			club: 'ARS',
			name: 'Declan Rice',
			event: 'buy',
			priceGbp: 1.42,
			size: 1240,
			totalGbp: 1760.8,
			feeGbp: 5.28,
			timestamp: NOW - 1 * DAY,
			txHash: '0xe5f4a3b2c1d0e9f8a7b6c5d4e3f2a1b0c9d8e7f6a5b4c3d2e1f0a9b8c7d6e5f4'
		},
		{
			image: '/tokens/playerToken.svg',
			alt: 'mSALA',
			symbol: 'mSALA',
			club: 'LIV',
			name: 'Mohamed Salah',
			event: 'buy',
			priceGbp: 3.5,
			size: 12,
			totalGbp: 42.0,
			feeGbp: 0.13,
			timestamp: NOW - 3 * DAY,
			txHash: '0xb8c7d6e5f4a3b2c1d0e9f8a7b6c5d4e3f2a1b0c9d8e7f6a5b4c3d2e1f0a9b8c7'
		},
		{
			image: '/tokens/playerToken.svg',
			alt: 'eHAAL',
			symbol: 'eHAAL',
			club: 'MCI',
			name: 'Erling Haaland',
			event: 'yield',
			priceGbp: null,
			size: 198.4,
			totalGbp: 198.4,
			feeGbp: null,
			timestamp: NOW - 8 * DAY,
			txHash: '0x9b8c7d6e5f4a3b2c1d0e9f8a7b6c5d4e3f2a1b0c9d8e7f6a5b4c3d2e1f0a9b8c'
		},
		{
			image: '/tokens/playerToken.svg',
			alt: 'bFERN',
			symbol: 'bFERN',
			club: 'MUN',
			name: 'Bruno Fernandes',
			event: 'buy',
			priceGbp: 1.18,
			size: 49,
			totalGbp: 57.82,
			feeGbp: 0.17,
			timestamp: NOW - 14 * DAY,
			txHash: '0xd8e7f6a5b4c3d2e1f0a9b8c7d6e5f4a3b2c1d0e9f8a7b6c5d4e3f2a1b0c9d8e7'
		},
		{
			image: '/tokens/playerToken.svg',
			alt: 'bSAKA',
			symbol: 'bSAKA',
			club: 'ARS',
			name: 'Bukayo Saka',
			event: 'buy',
			priceGbp: 2.05,
			size: 540,
			totalGbp: 1107.0,
			feeGbp: 3.32,
			timestamp: NOW - 35 * DAY,
			txHash: '0xf2a1b0c9d8e7f6a5b4c3d2e1f0a9b8c7d6e5f4a3b2c1d0e9f8a7b6c5d4e3f2a1'
		}
	];

	let query = $state('');
	let eventFilter = $state<EventFilter>('all');
	let range = $state<TimeRange>('7d');

	const LOADING_DURATION_MS = 1200;
	let isLoading = $state(true);

	$effect(() => {
		const timeoutId = setTimeout(() => {
			isLoading = false;
		}, LOADING_DURATION_MS);
		return () => clearTimeout(timeoutId);
	});

	function rangeStart(r: TimeRange): number {
		switch (r) {
			case '24h':
				return NOW - DAY;
			case '7d':
				return NOW - 7 * DAY;
			case '30d':
				return NOW - 30 * DAY;
			case 'all':
				return 0;
		}
	}

	const filtered = $derived(
		rows.filter((row) => {
			if (row.timestamp < rangeStart(range)) return false;
			if (eventFilter === 'trades' && row.event !== 'buy' && row.event !== 'sell') {
				return false;
			}
			if (eventFilter === 'cancelled' && row.event !== 'cancelled') return false;
			if (eventFilter === 'yield' && row.event !== 'yield') return false;
			if (query.trim().length > 0) {
				const q = query.trim().toLowerCase();
				return (
					row.symbol.toLowerCase().includes(q) || row.club.toLowerCase().includes(q)
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

	function formatAbsolute(ts: number): string {
		// 24-hour clock and short-month avoids the AM/PM clutter and locale-
		// dependent month names that get noisy at this row density.
		return new Date(ts).toLocaleString('en-GB', {
			day: '2-digit',
			month: 'short',
			hour: '2-digit',
			minute: '2-digit',
			hour12: false
		});
	}

	function formatRelative(ts: number): string {
		const diff = Math.max(0, NOW - ts);
		if (diff < HOUR) return `${Math.max(1, Math.floor(diff / MIN))}m ago`;
		if (diff < DAY) return `${Math.floor(diff / HOUR)}h ago`;
		return `${Math.floor(diff / DAY)}d ago`;
	}

	function shortHash(hash: string): string {
		return `${hash.slice(0, 6)}…${hash.slice(-4)}`;
	}

	function eventLabel(event: EventKind): string {
		switch (event) {
			case 'buy':
				return 'Buy';
			case 'sell':
				return 'Sell';
			case 'cancelled':
				return 'Cancelled';
			case 'yield':
				return 'Yield';
		}
	}
</script>

<div class="history">
	<div class="history-toolbar">
		<div class="history-toolbar-left">
			<div class="search">
				<i class="fa-solid fa-magnifying-glass search-icon" aria-hidden="true"></i>
				<input
					type="text"
					class="search-input"
					placeholder="Search asset"
					autocomplete="off"
					spellcheck="false"
					aria-label="Search history"
					bind:value={query}
				/>
			</div>
			<div class="filter-segments" role="tablist" aria-label="Event filter">
				{#each eventFilters as f (f.id)}
					<button
						type="button"
						class="filter-segment"
						class:filter-segment--active={eventFilter === f.id}
						role="tab"
						aria-selected={eventFilter === f.id}
						onclick={() => (eventFilter = f.id)}
					>
						{f.label}
					</button>
				{/each}
			</div>
		</div>
		<div class="history-toolbar-right">
			<div class="filter-segments" role="tablist" aria-label="Time range">
				{#each ranges as r (r.id)}
					<button
						type="button"
						class="filter-segment"
						class:filter-segment--active={range === r.id}
						role="tab"
						aria-selected={range === r.id}
						onclick={() => (range = r.id)}
					>
						{r.label}
					</button>
				{/each}
			</div>
		</div>
	</div>

	<div class="history-grid" role="grid" aria-rowcount={filtered.length + 1}>
		<div class="history-row history-row--head" role="row">
			<div class="cell cell--time" role="columnheader">Time</div>
			<div class="cell cell--asset" role="columnheader">Asset</div>
			<div class="cell" role="columnheader">Event</div>
			<div class="cell cell--num" role="columnheader">Price</div>
			<div class="cell cell--num" role="columnheader">Size</div>
			<div class="cell cell--num" role="columnheader">Total (GBP)</div>
			<div class="cell cell--num" role="columnheader">Fee</div>
			<div class="cell cell--tx" role="columnheader" aria-label="Transaction"></div>
		</div>

		<div class="history-body">
			{#each filtered as row, i (`${row.txHash}-${i}`)}
				<div class="history-row" role="row">
					<div class="cell cell--time" role="gridcell">
						<span class="time-abs">{formatAbsolute(row.timestamp)}</span>
						<span class="time-rel">{formatRelative(row.timestamp)}</span>
					</div>
					<div class="cell cell--asset" role="gridcell">
						<img src={row.image} alt={row.alt} class="asset-image" />
						<div class="asset-text">
							<span class="asset-symbol">{row.symbol}</span>
							<span class="asset-name">{row.name}</span>
						</div>
					</div>
					<div class="cell" role="gridcell">
						<span class="event-pill event-pill--{row.event}">
							{eventLabel(row.event)}
						</span>
					</div>
					<div
						class="cell cell--num"
						class:cell--muted={row.priceGbp === null}
						role="gridcell"
					>
						{row.priceGbp === null ? '—' : `£ ${formatGbp(row.priceGbp)}`}
					</div>
					<div class="cell cell--num" role="gridcell">{formatAmount(row.size)}</div>
					<div class="cell cell--num cell--value" role="gridcell">
						£ {formatGbp(row.totalGbp)}
					</div>
					<div
						class="cell cell--num"
						class:cell--muted={row.feeGbp === null}
						role="gridcell"
					>
						{row.feeGbp === null ? '—' : `£ ${formatGbp(row.feeGbp)}`}
					</div>
					<div class="cell cell--tx" role="gridcell">
						<a
							class="tx-link"
							href="#"
							title={row.txHash}
							aria-label="View transaction {shortHash(row.txHash)} on explorer"
						>
							<i class="fa-solid fa-arrow-up-right-from-square" aria-hidden="true"></i>
						</a>
					</div>
				</div>
			{:else}
				<div class="empty">
					<p class="empty-text">No history matches the current filters.</p>
				</div>
			{/each}
			<Loader visible={isLoading} label="Loading history" />
		</div>
	</div>
</div>

<style>
	.history {
		flex: 1 1 auto;
		min-height: 0;
		display: flex;
		flex-direction: column;
		align-items: stretch;
	}

	.history-toolbar {
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

	.history-toolbar-left,
	.history-toolbar-right {
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

	.history-grid {
		flex: 1 1 auto;
		min-height: 0;
		display: flex;
		flex-direction: column;
		align-items: stretch;
	}

	.history-row {
		display: grid;
		grid-template-columns:
			minmax(150px, 1.3fr)
			minmax(140px, 1.4fr)
			minmax(90px, 0.9fr)
			minmax(100px, 1fr)
			minmax(90px, 1fr)
			minmax(120px, 1fr)
			minmax(90px, 0.9fr)
			minmax(50px, auto);
		align-items: center;
		gap: 20px;
		padding: 0 20px;
		height: 48px;
		border-bottom: 1px solid var(--color-border-light);
		transition: background-color var(--transition-base);
	}

	.history-row--head {
		flex-shrink: 0;
		height: 32px;
		background-color: var(--color-surface-elevated);
	}

	.history-body {
		position: relative;
		flex: 1 1 auto;
		min-height: 0;
		overflow-y: auto;
	}

	.history-body::-webkit-scrollbar {
		width: 0;
	}

	.history-body::-webkit-scrollbar-track {
		background: transparent;
		border-radius: 0;
	}

	.history-body::-webkit-scrollbar-thumb {
		background: var(--color-border-strong);
		border-radius: 1px;
	}

	.history-body .history-row:hover {
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

	.history-row--head .cell {
		font-size: var(--text-xs);
		color: var(--color-text-muted);
		text-transform: uppercase;
	}

	.history-row--head .cell--time {
		display: block;
	}

	.cell--time {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		gap: 2px;
		min-width: 0;
	}

	.time-abs {
		font-size: var(--text-sm);
		color: var(--color-text);
		line-height: 1;
		font-variant-numeric: tabular-nums;
	}

	.time-rel {
		font-size: var(--text-xs);
		color: var(--color-text-muted);
		line-height: 1;
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

	.event-pill {
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

	.event-pill--buy {
		color: var(--color-success);
		background-color: color-mix(in oklab, var(--color-success) 12%, transparent);
		border-color: color-mix(in oklab, var(--color-success) 30%, transparent);
	}

	.event-pill--sell {
		color: var(--color-error);
		background-color: color-mix(in oklab, var(--color-error) 12%, transparent);
		border-color: color-mix(in oklab, var(--color-error) 30%, transparent);
	}

	.event-pill--cancelled {
		color: var(--color-text-muted);
		background-color: var(--color-surface-elevated);
		border-color: var(--color-border);
	}

	.event-pill--yield {
		color: var(--color-primary-light);
		background-color: color-mix(in oklab, var(--color-primary) 12%, transparent);
		border-color: color-mix(in oklab, var(--color-primary) 30%, transparent);
	}

	.cell--tx {
		display: flex;
		align-items: center;
		justify-content: flex-end;
		justify-self: end;
	}

	.tx-link {
		all: unset;
		box-sizing: border-box;
		width: 24px;
		height: 24px;
		display: inline-flex;
		align-items: center;
		justify-content: center;
		color: var(--color-text-muted);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-sm);
		background-color: var(--color-surface-elevated);
		cursor: pointer;
		transition:
			color var(--transition-base),
			border-color var(--transition-base),
			background-color var(--transition-base);
	}

	.tx-link:hover {
		color: var(--color-text);
		border-color: var(--color-border-strong);
		background-color: var(--color-surface-muted);
	}

	.tx-link i {
		font-size: 10px;
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
