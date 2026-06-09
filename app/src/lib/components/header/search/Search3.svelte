<script lang="ts">
    import Searchbox from './searchbox/Searchbox.svelte';

    interface Props {
        /** Seconds for one full scroll cycle */
        speed?: number;
        /** How many times the rate set is repeated in the marquee track. Must be >= 2. */
        copies?: number;
    }

    let { speed = 120, copies = 3 }: Props = $props();

    const rates = [
        { label: 'USD/GBP', value: '£0.75' },
        { label: 'SETH/GBP', value: '£15.49' },
        { label: 'ETH/GBP', value: '£1549.39' },
        // { label: 'HPI-30/GBP', value: '£1150.19' }
    ] as const;
</script>

<div class="search">
    <Searchbox />
    <div class="prices">
        <div class="prices-track" style="--duration: {speed}s; --copies: {copies};">
            {#each Array(copies) as _, copy}
                {#each rates as rate, i (`${copy}-${i}`)}
                    <div class="exchange-rate" aria-hidden={copy > 0}>
                        <p class="exchange-rate-label">{rate.label}</p>
                        <p class="exchange-rate-value">{rate.value}</p>
                    </div>
                {/each}
            {/each}
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
        justify-content: space-between;
        box-shadow: 0 0 10px 0 rgba(0, 0, 0, 0.1);
	}

	.prices {
        flex: 0.37;
		background-color: var(--color-surface-elevated);
		height: 100%;
        display: flex;
        align-items: center;
        border-left: 1px solid var(--color-border);
        position: relative;
        overflow: hidden;
	}

    .prices-track {
        display: flex;
        flex-direction: row;
        flex-wrap: nowrap;
        align-items: center;
        width: max-content;
        gap: 25px;
        padding-left: 25px;
        animation: prices-marquee var(--duration, 40s) linear infinite;
        will-change: transform;
        backface-visibility: hidden;
    }

    .prices:hover .prices-track {
        animation-play-state: paused;
    }

    .prices::before,
    .prices::after {
        content: '';
        position: absolute;
        top: 0;
        bottom: 0;
        width: 40px;
        z-index: 1;
        pointer-events: none;
    }

    .prices::before {
        left: 0;
        background: linear-gradient(to right, var(--color-surface-elevated), transparent);
    }

    .prices::after {
        right: 0;
        background: linear-gradient(to left, var(--color-surface-elevated), transparent);
    }

    .exchange-rate {
        display: flex;
        align-items: center;
        justify-content: center;
        gap: 4px;
        flex-shrink: 0;
        cursor: pointer;
        transition: opacity var(--transition-base);
    }

    .exchange-rate:active {
        opacity: 0.8;
    }

    .prices-track:has(.exchange-rate:hover) .exchange-rate:not(:hover) {
        opacity: 0.4;
    }

    @keyframes prices-marquee {
        from {
            transform: translateX(0);
        }
        to {
            transform: translateX(calc(-100% * (var(--copies, 3) - 1) / var(--copies, 3)));
        }
    }

    .exchange-rate-label {
        font-size: 10px;
        font-weight: 400;
        letter-spacing: 1px;
        color: var(--color-text-faded);
        margin-top: 2px;
    }

    .exchange-rate-value {
        font-size: 10px;
        font-weight: 400;
        letter-spacing: 1px;
        color: var(--color-text-faded);
        font-size: var(--text-sm);
    }

    .exchange-rate:hover .exchange-rate-label {
        color: var(--color-text-muted);
    }

    .exchange-rate:hover .exchange-rate-value {
        color: var(--color-text);
    }
</style>