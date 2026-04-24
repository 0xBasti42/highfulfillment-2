<script lang="ts">
	interface Props {
		data: { section: 'binaries' };
	}

	let { data }: Props = $props();
</script>

<svelte:head>
	<title>EPL | Binaries</title>
</svelte:head>

<div class="binaries" data-section={data.section}>
	<!-- Binaries content -->
</div>

<style>
	.binaries {
		flex: 1;
		min-height: 200px;
	}
</style>
