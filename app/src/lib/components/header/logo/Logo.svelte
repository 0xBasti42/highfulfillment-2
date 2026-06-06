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
			transform 300ms;
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
		filter: grayscale(1);
		/* `cubic-bezier(0.34, 1.56, 0.64, 1)` on transform is "back" easing —
		   the y-value > 1 makes the interpolation overshoot the target before
		   settling. That's what gives the press its springy bounce. Border,
		   opacity and filter stay on default easing — only the geometry
		   should spring. */
		transition:
			transform 300ms cubic-bezier(0.34, 1.56, 0.64, 1),
			border-color var(--transition-base),
			opacity var(--transition-base),
			filter var(--transition-base);
	}

	.logo:hover img {
		border-color: var(--color-border-strong);
		transform: translateX(3px);
		filter: grayscale(0);
	}

	.logo:active img {
		opacity: 0.7;
		transform: translateX(-3px);
	}

	/* On press, the dots are pushed further left and fade — they read as
	   scattering away from the encroaching logo rather than disappearing in
	   place. Source-ordered after `:hover` so it wins when both states are
	   true (mouse-down on a hovered logo). */
	.logo:active::before {
		opacity: 0;
		transform: translate(-6px, -50%);
	}
</style>
