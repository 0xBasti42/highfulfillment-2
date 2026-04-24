<script lang="ts">
	import { onMount } from 'svelte';
	import FixtureMarquee from './FixtureMarquee.svelte';

	interface Props {
		matchweekNumber?: number;
		deadline?: Date;
	}

	let {
		matchweekNumber = 35,
		deadline = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000)
	}: Props = $props();

	// `now` stays null during SSR so the countdown doesn't render on the server
	// (avoids a hydration mismatch from clock drift between server and client).
	let now = $state<number | null>(null);

	onMount(() => {
		now = Date.now();
		const id = setInterval(() => {
			now = Date.now();
		}, 1000);
		return () => clearInterval(id);
	});

	const countdown = $derived.by(() => {
		if (now === null) return '';
		const remaining = Math.max(0, deadline.getTime() - now);
		const days = Math.floor(remaining / 86_400_000);
		const hrs = Math.floor((remaining / 3_600_000) % 24);
		const mins = Math.floor((remaining / 60_000) % 60);
		const secs = Math.floor((remaining / 1_000) % 60);
		return `${days} days, ${hrs} hrs, ${mins} mins, ${secs} secs`;
	});
</script>

<div class="rolling-text">
	<div class="rolling-text-left">
		<p class="rolling-text-title">Matchweek {matchweekNumber}</p>
		<p class="rolling-text-countdown">{countdown}</p>
	</div>
	<div class="rolling-text-right">
		<FixtureMarquee count={10} />
	</div>
</div>

<style>
	.rolling-text {
		height: 45px;
		display: flex;
		flex-direction: row;
		align-items: stretch;
		border-bottom: 1px solid var(--color-border);
		background-color: var(--color-surface);
	}

	.rolling-text-left {
		width: 260px;
		flex-shrink: 0;
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		justify-content: center;
		gap: 4px;
		padding: 0 20px;
		padding-bottom: 2px;
	}

	.rolling-text-title {
		margin: 0;
		font-size: var(--text-xs);
		line-height: 1;
	}

	.rolling-text-countdown {
		margin: 0;
		font-size: var(--text-sm);
		color: var(--color-text);
		line-height: 1;
		font-variant-numeric: tabular-nums;
	}

	.rolling-text-right {
		flex: 1;
		min-width: 0;
	}
</style>
