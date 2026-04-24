<script lang="ts">
	interface Props {
		data: { section: 'fixtures' };
	}

	let { data }: Props = $props();
</script>

<svelte:head>
	<title>EPL | Fixtures</title>
</svelte:head>

<div class="fixtures" data-section={data.section}>
	<!-- Fixtures content -->
</div>

<style>
	.fixtures {
		flex: 1;
		min-height: 200px;
	}
</style>
