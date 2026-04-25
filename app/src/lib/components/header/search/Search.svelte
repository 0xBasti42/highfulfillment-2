<script lang="ts">
    import Searchbox from './searchbox/Searchbox.svelte';
</script>

<div class="search">
    <Searchbox />
    <div class="prices">
        <div class="exchange-rate">
            <p class="exchange-rate-label">USD/GBP</p>
            <p class="exchange-rate-value">£0.75</p>
        </div>
        <div class="exchange-rate">
            <p class="exchange-rate-label">sETH/GBP</p>
            <p class="exchange-rate-value">£15.49</p>
        </div>
        <div class="exchange-rate">
            <p class="exchange-rate-label">ETH/GBP</p>
            <p class="exchange-rate-value">£1549.39</p>
        </div>
    </div>
</div>

<style>
	.search {
        background-color: var(--color-surface-elevated);
		border-bottom: 1px solid var(--color-border);
        height: 60px;
        display: flex;
        align-items: center;
        justify-content: flex-start;
        box-shadow: 0 0 10px 0 rgba(0, 0, 0, 0.1);
	}

	.prices {
        flex: 1;
		background-color: var(--color-surface-elevated);
		border-bottom: 1px solid var(--color-border);
		height: 60px;
		display: flex;
		align-items: center;
		justify-content: flex-end;
		padding: 0 20px;
        gap: 25px;
	}

    .exchange-rate {
        display: flex;
        align-items: center;
        justify-content: center;
        gap: 4px;
    }

    .exchange-rate-label {
        font-size: 10px;
        font-weight: 400;
        letter-spacing: 1px;
        color: var(--color-text-muted);
        margin-top: 2px;
    }

    .exchange-rate-value {
        font-size: 10px;
        font-weight: 400;
        letter-spacing: 1px;
        color: var(--color-text);
        font-size: var(--text-sm);
    }
</style>