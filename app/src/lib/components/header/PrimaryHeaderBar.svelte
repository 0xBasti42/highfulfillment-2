<script lang="ts">
	import Logo from './logo/Logo.svelte';
	import MainMenu from './main-menu/MainMenu.svelte';
	import NetworkSelector from './network-selector/NetworkSelector.svelte';
	import { signup } from '$lib/state/signup.svelte';
</script>

<div class="header">
    <div class="header-left">
        <Logo />
        <MainMenu />
    </div>
    <div class="header-right">
        <div class="header-right-item">
            <NetworkSelector />
        </div>
        <div class="header-right-item">
            <button type="button" class="button" onclick={() => signup.open()}>Connect</button>
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
        gap: 10px;
    }

    .header-right-item {
        display: flex;
        flex-direction: row;
        align-items: center;
        justify-content: flex-end;
        gap: 25px;
        cursor: default;
    }

    .button {
        height: 25px;
        width: 142px;
        font-size: 11px;
        transition: all var(--transition-base);
    }

    .button:active {
        opacity: 1;
    }
</style>