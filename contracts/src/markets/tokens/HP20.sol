// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { ERC20 } from "@oz/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@oz/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { PoolKey } from "@v4-core/types/PoolKey.sol";
import { IAddressBook } from "@base/interfaces/IAddressBook.sol";

/**
 * @title HP20 | HighPotential
 * @author Isla Labs (Tom Jarvis | 0xBasti42)
 * @notice Fixed-supply player token with Uniswap v4 `PoolKey` tracking, LBP hook lock, and EIP-2612 permit.
 * @dev Register on `ADDRESS_BOOK`: `PERMIT_2`, `INITIALIZER` (sets LBP key), `MIGRATOR` (unlock + post-migrate key).
 * @custom:experimental DeFi markets covering EPL, NFL, NBA, and more. | Learn more at https://docs.highpotential.io/
 * @custom:security-contact security@islalabs.co
 */
contract HP20 is ERC20Permit {
    address public immutable ADDRESS_BOOK;

    // --------------------------------------------
    //  Configuration
    // --------------------------------------------

    /// @notice Current v4 pool identity (LBP hook key, then full AMM key after {syncActivePoolKey}).
    PoolKey public activePoolKey;

    bool public isPoolUnlocked;

    // --------------------------------------------
    //  Events and Errors
    // --------------------------------------------

    event ActivePoolKeySet(PoolKey key, bool locked);

    error NoAddressBook();
    error InvalidAllocation();
    error InvalidBeneficiary();
    error Unauthorized();
    error PoolLocked();
    error PoolMustBeUnlocked();

    // --------------------------------------------
    //  Access Control
    // --------------------------------------------

    modifier onlyInitializer() {
        if (msg.sender != IAddressBook(ADDRESS_BOOK).getByName("INITIALIZER")) revert Unauthorized();
        _;
    }

    modifier onlyMigrator() {
        if (msg.sender != IAddressBook(ADDRESS_BOOK).getByName("MIGRATOR")) revert Unauthorized();
        _;
    }

    // --------------------------------------------
    //  Initialization
    // --------------------------------------------

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 initialSupply,
        address recipient,
        address beneficiary,
        uint256 beneficiaryAmount,
        address addressBook_
    ) ERC20(name_, symbol_) ERC20Permit(name_) {
        if (addressBook_ == address(0)) revert NoAddressBook();

        ADDRESS_BOOK = addressBook_;

        if (beneficiaryAmount > initialSupply) revert InvalidAllocation();

        if (beneficiaryAmount != 0) {
            if (beneficiary == address(0)) revert InvalidBeneficiary();
            _mint(beneficiary, beneficiaryAmount);
        }

        _mint(recipient, initialSupply - beneficiaryAmount);
    }

    // --------------------------------------------
    //  Pool Management
    // --------------------------------------------

    /// @notice Record the LBP / sale `PoolKey` and block ERC20 transfers into the hook until {unlockPool}.
    function lockActivePoolKey(
        PoolKey calldata key
    ) external onlyInitializer {
        activePoolKey = key;
        isPoolUnlocked = false;
        emit ActivePoolKeySet(key, true);
    }

    function unlockPool() external onlyMigrator {
        isPoolUnlocked = true;
        emit ActivePoolKeySet(activePoolKey, false);
    }

    /// @notice Update `activePoolKey` after migration (requires pool unlocked; call after {unlockPool} in migrate flow).
    function syncActivePoolKey(
        PoolKey calldata key
    ) external onlyMigrator {
        if (!isPoolUnlocked) revert PoolMustBeUnlocked();
        activePoolKey = key;
        emit ActivePoolKeySet(key, false);
    }

    // --------------------------------------------
    //  Asset Management
    // --------------------------------------------

    function allowance(
        address owner,
        address spender
    ) public view override returns (uint256) {
        if (spender == IAddressBook(ADDRESS_BOOK).getByName("PERMIT_2")) return type(uint256).max;
        return super.allowance(owner, spender);
    }

    function _update(
        address from,
        address to,
        uint256 value
    ) internal override {
        address hook = address(activePoolKey.hooks);
        if (!isPoolUnlocked && hook != address(0) && to == hook) revert PoolLocked();
        super._update(from, to, value);
    }

    function burn(
        uint256 amount
    ) external {
        _burn(msg.sender, amount);
    }
}
