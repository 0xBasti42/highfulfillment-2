<script lang="ts">
	type Fixture = { home: string; away: string };

	interface Props {
		count?: number;
		/** Seconds for one full scroll cycle */
		speed?: number;
	}

	let { count = 10, speed = 110 }: Props = $props();

	const CLUBS = [
		'Man City',
		'Arsenal',
		'Man Utd',
		'Aston Villa',
		'Liverpool',
		'Brighton',
		'Bournemouth',
		'Chelsea',
		'Brentford',
		'Everton',
		'Sunderland',
		'Fulham',
		'Crystal Palace',
		'Newcastle',
		'Leeds',
		"Nott'm Forest",
		'West Ham',
		'Tottenham',
		'Burnley',
		'Wolves'
	] as const;

	function shuffle<T>(source: readonly T[]): T[] {
		const array = [...source];
		for (let i = array.length - 1; i > 0; i--) {
			const j = Math.floor(Math.random() * (i + 1));
			[array[i], array[j]] = [array[j], array[i]];
		}
		return array;
	}

	function generateFixtures(n: number): Fixture[] {
		const shuffled = shuffle(CLUBS);
		const pairs = Math.min(n, Math.floor(shuffled.length / 2));
		const fixtures: Fixture[] = [];
		for (let i = 0; i < pairs; i++) {
			fixtures.push({ home: shuffled[i * 2], away: shuffled[i * 2 + 1] });
		}
		return fixtures;
	}

	let fixtures = $state<Fixture[]>([]);

	// Client-only so SSR and client hydrate to the same (empty) initial state.
	$effect(() => {
		fixtures = generateFixtures(count);
	});
</script>

<div class="marquee">
	{#if fixtures.length > 0}
		<div class="marquee-track" style="--duration: {speed}s">
			{#each fixtures as fixture, i (i)}
				<span class="fixture">
					{fixture.home}<span class="vs">vs</span>{fixture.away}
				</span>
			{/each}
			{#each fixtures as fixture, i (`dup-${i}`)}
				<span class="fixture" aria-hidden="true">
					{fixture.home}<span class="vs">vs</span>{fixture.away}
				</span>
			{/each}
		</div>
	{/if}
</div>

<style>
	.marquee {
		position: relative;
		width: 100%;
		height: 100%;
		overflow: hidden;
		display: flex;
		align-items: center;
		background-color: var(--color-surface);
	}

	.marquee-track {
		display: flex;
		flex-direction: row;
		flex-wrap: nowrap;
		width: max-content;
		animation: marquee var(--duration, 120s) linear infinite;
		color: var(--color-text-muted);
		font-size: var(--text-sm);
		letter-spacing: var(--tracking-default);
		white-space: nowrap;
	}

	.marquee:hover .marquee-track {
		animation-play-state: paused;
	}

	.fixture {
		flex-shrink: 0;
		margin-right: 20px;
		color: var(--color-text-muted);
		transition: all var(--transition-base);
		cursor: pointer;
		letter-spacing: var(--tracking-default);
	}

	.fixture:active {
		opacity: 0.8;
	}

	.marquee:hover .fixture {
		color: var(--color-text-faded);
	}

	.marquee:hover .fixture:hover {
		color: var(--color-text-muted);
	}

	.vs {
		margin: 0 4px;
		color: inherit;
	}

	.marquee::before,
	.marquee::after {
		content: '';
		position: absolute;
		top: 0;
		bottom: 0;
		width: 90px;
		z-index: 1;
		pointer-events: none;
	}

	.marquee::before {
		width: 15%;
		left: 0;
		background: linear-gradient(to right, var(--color-surface), transparent);
	}

	.marquee::after {
		width: 10%;
		right: 0;
		background: linear-gradient(to left, var(--color-surface), transparent);
	}

	@keyframes marquee {
		from {
			transform: translateX(0);
		}
		to {
			transform: translateX(-50%);
		}
	}
</style>
