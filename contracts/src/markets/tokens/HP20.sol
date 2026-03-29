// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { ERC20 } from "@oz/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@oz/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { PoolKey } from "@v4-core/types/PoolKey.sol";
import { IAddressBook } from "@base/interfaces/IAddressBook.sol";

/**
 * @title HP20 | HighPotential
 * @author Isla Labs (Tom Jarvis | 0xBasti42)
 * @notice Fixed-supply player token with Uniswap v4 `PoolKey` tracking, LBP hook lock, EIP-2612 permit, and URI metadata.
 * @dev Register on `ADDRESS_BOOK`: `PERMIT_2`, `INITIALIZER`, `MIGRATOR`, `METADATA_ADMIN` (updates URI / hash).
 * @custom:experimental DeFi markets covering EPL, NFL, NBA, and more. | Learn more at https://docs.highpotential.io/
 * @custom:security-contact security@islalabs.co
 */
contract HP20 is ERC20Permit {
    address public immutable ADDRESS_BOOK;

    // --------------------------------------------
    //  Metadata
    // --------------------------------------------

    /// @notice Location of ERC20 metadata JSON (HTTPS / IPFS, etc.). Query on-chain via `tokenURI()`; off-chain via the same ABI read.
    string public tokenURI;

    /// @notice Optional commitment to canonical JSON (e.g. keccak256 of UTF-8 bytes). Zero if unused.
    bytes32 public metadataHash;

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
    event TokenURIUpdated(string newURI);
    event MetadataHashUpdated(bytes32 newHash);

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

    modifier onlyOrchestrator() {
        if (msg.sender != IAddressBook(ADDRESS_BOOK).getByName("ORCHESTRATOR")) revert Unauthorized();
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
        address addressBook_,
        string memory tokenURI_,
        bytes32 metadataHash_
    ) ERC20(name_, symbol_) ERC20Permit(name_) {
        if (addressBook_ == address(0)) revert NoAddressBook();

        ADDRESS_BOOK = addressBook_;
        tokenURI = tokenURI_;
        metadataHash = metadataHash_;

        if (beneficiaryAmount > initialSupply) revert InvalidAllocation();

        if (beneficiaryAmount != 0) {
            if (beneficiary == address(0)) revert InvalidBeneficiary();
            _mint(beneficiary, beneficiaryAmount);
        }

        _mint(recipient, initialSupply - beneficiaryAmount);
    }

    // --------------------------------------------
    //  Metadata (updates)
    // --------------------------------------------

    function setTokenURI(string calldata newURI) external onlyOrchestrator {
        tokenURI = newURI;
        emit TokenURIUpdated(newURI);
    }

    function setMetadataHash(bytes32 newHash) external onlyOrchestrator {
        metadataHash = newHash;
        emit MetadataHashUpdated(newHash);
    }

    // --------------------------------------------
    //  Pool Management
    // --------------------------------------------

    /// @notice Record the LBP / sale `PoolKey` and block ERC20 transfers into the hook until {unlockPool}.
    function lockActivePoolKey(PoolKey calldata key) external onlyInitializer {
        activePoolKey = key;
        isPoolUnlocked = false;
        emit ActivePoolKeySet(key, true);
    }

    function unlockPool() external onlyMigrator {
        isPoolUnlocked = true;
        emit ActivePoolKeySet(activePoolKey, false);
    }

    /// @notice Update `activePoolKey` after migration (requires pool unlocked; call after {unlockPool} in migrate flow).
    function syncActivePoolKey(PoolKey calldata key) external onlyMigrator {
        if (!isPoolUnlocked) revert PoolMustBeUnlocked();
        activePoolKey = key;
        emit ActivePoolKeySet(key, false);
    }

    // --------------------------------------------
    //  Asset Management
    // --------------------------------------------

    function allowance(address owner, address spender) public view override returns (uint256) {
        if (spender == IAddressBook(ADDRESS_BOOK).getByName("PERMIT_2")) return type(uint256).max;
        return super.allowance(owner, spender);
    }

    function _update(address from, address to, uint256 value) internal override {
        address hook = address(activePoolKey.hooks);
        if (!isPoolUnlocked && hook != address(0) && to == hook) revert PoolLocked();
        super._update(from, to, value);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}
