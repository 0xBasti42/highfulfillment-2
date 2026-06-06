/**
 * Shared open/close state for the signup / sign-in modal.
 *
 * Lives outside any component so triggers (e.g. the Connect button in the
 * header) and the modal itself (mounted at the layout root, like Sidebar)
 * can share a single source of truth without prop drilling.
 *
 * Mirrors the pattern in `sidebar.svelte.ts`.
 */

let _isOpen = $state(false);

export const signup = {
	get isOpen() {
		return _isOpen;
	},
	open() {
		_isOpen = true;
	},
	close() {
		_isOpen = false;
	},
	toggle() {
		_isOpen = !_isOpen;
	}
};
