<script lang="ts">
	import { sidebar } from '$lib/state/sidebar.svelte';
</script>

<button
	type="button"
	class="logo"
	aria-label="Open menu"
	aria-expanded={sidebar.isOpen}
	aria-controls="app-sidebar"
	onclick={() => sidebar.toggle()}
>
	<img src="/brand/icon-dark.svg" alt="Logo" />
</button>

<style>
	.logo {
		all: unset;
		position: relative;
		width: auto;
		height: 25px;
		display: flex;
		align-items: center;
		justify-content: flex-start;
		gap: 10px;
		box-shadow: 0 0 10px 0 rgba(0, 0, 0, 0.1);
		cursor: pointer;
	}

	/* Three small round dots stacked vertically as a hover indicator.
	   The element paints the middle dot directly; `box-shadow` paints the
	   two flanking dots at ±5px Y so the whole stack is one positioned box. */
	.logo::before {
		content: '';
		position: absolute;
		left: -8px;
		top: 50%;
		width: 3px;
		height: 3px;
		background-color: var(--color-border-strong);
		border-radius: 50%;
		box-shadow:
			0 -5px 0 var(--color-border-strong),
			0 5px 0 var(--color-border-strong);
		transform: translate(-2px, -50%);
		transition:
			opacity var(--transition-base),
			transform var(--transition-base);
		pointer-events: none;
		opacity: 0;
	}

	.logo:hover::before {
		opacity: 1;
		transform: translate(0, -50%);
	}

	.logo img {
		width: 25px;
		height: 25px;
		border-radius: 5px;
		border: 1px solid var(--color-border);
		transition: all var(--transition-base);
	}

	.logo:hover img {
		border: 1px solid var(--color-border-strong);
		transform: translateX(3px);
	}

	.logo:active img {
		opacity: 0.7;
	}
</style>
