// SPDX-License-Identifier: MIT
// Modified from OpenZeppelin Contracts v5.3.0 (utils/Pausable.sol).
// Adapted for EIP-2535 diamond facets: each inheriting facet binds its own
// namespaced storage slot at construction time so that pause flags never
// collide when multiple facets share a diamond's storage context.

pragma solidity ^0.8.20;

import {Context} from "@openzeppelin/contracts/utils/Context.sol";

abstract contract Pausable is Context {
    /// @dev Storage slot inside the diamond where this facet's pause flag lives.
    ///      Baked into the facet's bytecode via `immutable`, so it survives
    ///      delegatecall from the diamond.
    bytes32 private immutable _PAUSE_SLOT;

    /// @dev Wrapping the flag in a struct leaves room to extend the record
    ///      (e.g. `uint40 pausedAt`, `bytes32 reason`) without moving slots.
    struct PauseStorage {
        bool paused;
    }

    event Paused(address account);
    event Unpaused(address account);

    error EnforcedPause();
    error ExpectedPause();
    error ZeroPauseSlot();

    /// @param pauseSlot Unique slot for this facet's pause state. Recommended:
    ///                  `keccak256("hp.<facet>.<version>.pause.storage")`.
    constructor(bytes32 pauseSlot) {
        if (pauseSlot == bytes32(0)) revert ZeroPauseSlot();
        _PAUSE_SLOT = pauseSlot;
    }

    function _pauseStorage() private view returns (PauseStorage storage p) {
        bytes32 slot = _PAUSE_SLOT;
        assembly { p.slot := slot }
    }

    modifier whenNotPaused() {
        _requireNotPaused();
        _;
    }

    modifier whenPaused() {
        _requirePaused();
        _;
    }

    function paused() public view virtual returns (bool) {
        return _pauseStorage().paused;
    }

    function _requireNotPaused() internal view virtual {
        if (paused()) revert EnforcedPause();
    }

    function _requirePaused() internal view virtual {
        if (!paused()) revert ExpectedPause();
    }

    function _pause() internal virtual whenNotPaused {
        _pauseStorage().paused = true;
        emit Paused(_msgSender());
    }

    function _unpause() internal virtual whenPaused {
        _pauseStorage().paused = false;
        emit Unpaused(_msgSender());
    }
}