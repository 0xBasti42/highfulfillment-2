<script lang="ts">
	import Chart from './chart/Chart.svelte';
	import PositionView from './position-view/PositionView.svelte';

	interface Props {
		data: { section: 'markets' };
	}

	let { data }: Props = $props();

	let activeCurrency = $state('USD');
</script>

<svelte:head>
	<title>EPL | mGABR-{activeCurrency}</title>
</svelte:head>

<div class="markets" data-section={data.section}>
	<Chart />
	<PositionView />
</div>

<style>
	.markets {
		flex: 1;
		min-height: 200px;
		display: flex;
		flex-direction: column;
		align-items: stretch;
	}
</style>
