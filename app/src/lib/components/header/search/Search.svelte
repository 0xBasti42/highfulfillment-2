<script lang="ts">
    import Searchbox from './searchbox/Searchbox.svelte';

    const rates = [
        { label: 'USD/GBP', value: '£ 0.7531' },
        { label: 'sETH/GBP', value: '£ 15.490' },
        { label: 'ETH/GBP', value: '£ 1549.39' },
        { label: 'HPI-30/GBP', value: '£ 1150.19' }
    ] as const;
</script>

<div class="search">
    <Searchbox />
    <div class="prices">
        {#each rates as rate (rate.label)}
            <div class="exchange-rate">
                <p class="exchange-rate-label label-eyebrow">{rate.label}</p>
                <p class="exchange-rate-value">{rate.value}</p>
            </div>
        {/each}
    </div>
</div>

<style>
	.search {
        background-color: var(--color-surface-elevated);
		border-bottom: 1px solid var(--color-border);
        height: 60px;
        display: flex;
        align-items: center;
        justify-content: space-between;
        box-shadow: 0 0 10px 0 rgba(0, 0, 0, 0.1);
	}

	.prices {
        flex: 0 0 var(--side-width);
		background-color: var(--color-surface-elevated);
		height: 100%;
        display: flex;
        align-items: center;
        gap: 25px;
        padding-left: 20px;
        border-left: 1px solid var(--color-border);
        overflow: hidden;
	}

    .exchange-rate {
        display: flex;
        flex-direction: column;
        align-items: flex-start;
        justify-content: center;
        gap: 4px;
        flex-shrink: 0;
        cursor: pointer;
        transition: opacity var(--transition-base);
        margin-bottom: 2px;
    }

    .prices:hover .exchange-rate {
        opacity: 0.4;
    }

    .prices:hover .exchange-rate:hover {
        opacity: 1;
    }

    .prices:hover .exchange-rate:active {
        opacity: 0.8;
    }

    .exchange-rate-label {
        margin-top: 2px;
        line-height: 1;
        font-size: 9px;
    }

    .exchange-rate-value {
        font-size: 10px;
        font-weight: 400;
        letter-spacing: 1px;
        color: var(--color-text);
        font-size: var(--text-sm);
        line-height: 1;
    }
</style>