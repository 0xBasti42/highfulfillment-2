<script lang="ts">
</script>

<div class="searchbox">
    <img src="/icons/search.svg" alt="Search" style="width: 15px; height: 15px; cursor: pointer;" />
    <p>Search markets, fixtures, clubs, etc.</p>
</div>

<style>
	.searchbox {
        background-color: var(--color-surface-muted);
		border: 1px solid var(--color-border-light);
		border-left: none;
		border-radius: 0 var(--radius-pill) var(--radius-pill) 0;
		height: 30px;
		width: 33%;
		padding: 0 10px 0 20px;
        display: flex;
        align-items: center;
        justify-content: flex-start;
        gap: 10px;
		cursor: text;
		transition: all var(--transition-base);
	}

	.searchbox:hover {
		background-color: #252525;
		border-left: none;
	}

	.searchbox:hover p {
		color: var(--color-text-muted);
	}

	.searchbox:active {
		background-color: var(--color-surface-muted);
		border: 1px solid var(--color-border);
		border-left: none;
	}

	.searchbox:active p {
		color: var(--color-text-muted);
	}
</style>
