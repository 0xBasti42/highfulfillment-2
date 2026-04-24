<script lang="ts">
	import Logo from './logo/Logo.svelte';
	import MainMenu from './main-menu/MainMenu.svelte';
</script>

<div class="header">
    <div class="header-left">
        <Logo />
        <MainMenu />
    </div>
    <div class="header-right">
        <div class="header-right-item">
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
        <div class="header-right-item">
            <button class="button">Connect</button>
        </div>
    </div>
</div>

<style>
	.header {
        background-color: var(--color-surface-elevated);
		border-bottom: 1px solid var(--color-border);
        height: 50px;
        display: flex;
        align-items: center;
        justify-content: flex-start;
        padding: 0 20px;
        box-shadow: 0 0 10px 0 rgba(0, 0, 0, 0.1);
	}

    .header-left {
        flex: 1;
        display: flex;
        align-items: center;
        justify-content: flex-start;
        gap: 0;
    }

    .header-right {
        flex: 1;
        display: flex;
        align-items: center;
        justify-content: flex-end;
        gap: 25px;
    }

    .header-right-item {
        display: flex;
        flex-direction: row;
        align-items: center;
        justify-content: flex-end;
        gap: 25px;
        cursor: default;
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

    .button {
        height: 25px;
        width: 142px;
        font-size: 11px;
        transition: all var(--transition-base);
    }
</style>