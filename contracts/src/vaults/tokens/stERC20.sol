// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { ERC20 } from "@openzeppelin/token/ERC20/ERC20.sol";
import { ERC20Snapshot } from "src/extensions/ERC20Snapshot.sol";
import { ERC20Permit } from "@openzeppelin/token/ERC20/extensions/ERC20Permit.sol";

/**
 * @title HighPotential Staked Token (st.TOKEN)
 * @notice Non-transferable except to/from its corresponding PlayerVault.
 * @custom:security-contact security@islalabs.co
 */
contract STERC20 is ERC20, ERC20Snapshot, ERC20Permit {
    address public immutable vault;

    error OnlyVault();

    constructor(
        string memory name_,
        string memory symbol_,
        address vault_,
        uint256 initialSupplyToVault
    ) ERC20(name_, symbol_) ERC20Permit(name_) {
        require(vault_ != address(0), "VAULT_ZERO");
        vault = vault_;
        if (initialSupplyToVault > 0) _mint(vault_, initialSupplyToVault);
    }

    // Restrict transfers so that either the sender or the recipient is the vault.
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override(ERC20, ERC20Snapshot) {
        if (from != address(0) && to != address(0)) {
            // both sides non-zero => regular transfer
            if (from != vault && to != vault) revert OnlyVault();
        }
        super._update(from, to, value);
    }

    // Expose snapshot to vault
    function snapshot() external returns (uint256) {
        if (msg.sender != vault) revert OnlyVault();
        return _snapshot();
    }
}
