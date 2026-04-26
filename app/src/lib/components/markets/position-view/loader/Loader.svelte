<script lang="ts">
	/**
	 * Overlay loader for the position-view list area. Mirrors the styling and
	 * fade-timing of `Chart.svelte`'s inline loader, but scoped per-tab so it
	 * covers only the scrollable list body — toolbars and grid head rows
	 * remain interactive while loading.
	 *
	 * Requires its parent to be `position: relative` (the absolute `inset: 0`
	 * positioning targets the nearest positioned ancestor's padding box).
	 */
	interface Props {
		visible: boolean;
		label?: string;
	}

	let { visible, label = 'Loading' }: Props = $props();
</script>

<div
	class="loader"
	class:loader--visible={visible}
	role="status"
	aria-label={label}
	aria-hidden={!visible}
>
	<div class="loader__spinner"></div>
</div>

<style>
	.loader {
		position: absolute;
		inset: 0;
		z-index: 5;
		display: flex;
		align-items: center;
		justify-content: center;
		background-color: var(--color-surface-elevated);
		visibility: hidden;
		pointer-events: none;
		opacity: 0;
		/* Delay the visibility flip until the opacity fade-out finishes —
		   without this, the element jumps to hidden before the fade plays. */
		transition:
			opacity var(--transition-slow),
			visibility 0s linear var(--transition-slow);
	}

	.loader--visible {
		visibility: visible;
		pointer-events: auto;
		opacity: 1;
		/* On fade-in, visibility flips immediately so the element is visible
		   while opacity transitions from 0 to 1. */
		transition: opacity var(--transition-slow);
	}

	.loader__spinner {
		width: 32px;
		height: 32px;
		border: 2px solid var(--color-surface-muted);
		border-top-color: var(--color-text);
		border-radius: 50%;
		animation: loader-spin 0.8s linear infinite;
	}

	@keyframes loader-spin {
		to {
			transform: rotate(360deg);
		}
	}
</style>
