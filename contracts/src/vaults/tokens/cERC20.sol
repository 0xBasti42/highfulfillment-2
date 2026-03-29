// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { ERC20Snapshot } from "@base/ERC20Snapshot.sol";

contract CVCERC20 is ERC20Snapshot {
    address public immutable vault;

    error OnlyVault();
    error AlreadyHasFlag();
    error NoFlag();

    modifier onlyVault() {
        if (msg.sender != vault) revert OnlyVault();
        _;
    }

    constructor(string memory name_, string memory symbol_, address vault_) ERC20(name_, symbol_) {
        require(vault_ != address(0), "VAULT_ZERO");
        vault = vault_;
    }

    // 1 unit minted/burned per set/unset; enforce 0/1 per holder
    function mint(address to) external onlyVault {
        if (balanceOf(to) != 0) revert AlreadyHasFlag();
        _mint(to, 1);
    }

    function burn(address from) external onlyVault {
        if (balanceOf(from) == 0) revert NoFlag();
        _burn(from, 1);
    }

    // Vault takes snapshots atomically with stake snapshot
    function snapshot() external onlyVault returns (uint256) {
        return _snapshot();
    }

    // Non-transferable: allow only mint/burn paths
    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Snapshot) {
        require(from == address(0) || to == address(0), "NON_TRANSFERABLE");
        super._update(from, to, value);
    }
}
