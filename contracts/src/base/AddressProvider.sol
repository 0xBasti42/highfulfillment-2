// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

/// @notice Minimal read surface for dependent contracts; prefer casting to `AddressProvider` when you need individual getters.
interface IAddressProvider {
    function version() external view returns (uint256);
    function getAddresses() external view returns (Addresses memory);
}

/// @dev Canonical packed config for deployment and updates. Integrators should treat zero addresses as “unset”.
struct Addresses {
    address safe;
    address orchestrator;
    address registry;
    address airlock;
    address poolManager;
    address positionManager;
    address tokenFactory;
    address noOpGovernanceFactory;
    address stakeRouter;
    address swapRouter;
    address limitRouter;
    address quoteRouter;
    address airlockWrapper;
    address deployer;
    address initializer;
    address deploymentForwarder;
    address migrator;
    address migratorHook;
    address migrationForwarder;
    address recycler;
    address discontinuationForwarder;
    address nftStorageFactory;
    address nftStorageBeacon;
    address vaultFactory;
    address treasury;
    address vaultBeacon;
    address vaultTokenFactory;
    address squadCheck;
    address pbrForwarder;
    address eth;
    address usdc;
}

/// @title HighPotential Address Provider
/// @notice Central registry for protocol addresses. Mutability is role-gated (no proxy). Version increments on each full config write.
contract AddressProvider is AccessControl {
    /// @notice Role allowed to call {setAddresses}. Admin can grant this to ops / multisig separate from `DEFAULT_ADMIN_ROLE`.
    bytes32 public constant ADDRESS_MANAGER_ROLE = keccak256("ADDRESS_MANAGER_ROLE");

    /// @notice Monotonic config generation: `1` after constructor, then +1 on each successful {setAddresses}.
    uint256 public version;

    address public safe;
    address public orchestrator;
    address public registry;

    // --- Doppler / launch ---
    address public airlock;
    address public poolManager;
    address public positionManager;
    address public tokenFactory;
    address public noOpGovernanceFactory;

    // --- Exchange ---
    address public stakeRouter;
    address public swapRouter;
    address public limitRouter;
    address public quoteRouter;

    // --- Markets ---
    address public airlockWrapper;
    address public deployer;
    address public initializer;
    address public deploymentForwarder;
    address public migrator;
    address public migratorHook;
    address public migrationForwarder;
    address public recycler;
    address public discontinuationForwarder;
    address public nftStorageFactory;
    address public nftStorageBeacon;

    // --- Vaults ---
    address public vaultFactory;
    address public treasury;
    address public vaultBeacon;
    address public vaultTokenFactory;
    address public squadCheck;
    address public pbrForwarder;

    // --- Quote assets ---
    address public eth;
    address public usdc;

    event AddressesUpdated(uint256 indexed version, Addresses config);

    error ZeroDefaultAdmin();

    /// @param defaultAdmin Receives `DEFAULT_ADMIN_ROLE` and `ADDRESS_MANAGER_ROLE` (split responsibilities after deploy via `grantRole` / `revokeRole`).
    /// @param initial Full initial address set (zeros allowed for phased rollout).
    constructor(
        address defaultAdmin,
        Addresses memory initial
    ) {
        if (defaultAdmin == address(0)) revert ZeroDefaultAdmin();
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(ADDRESS_MANAGER_ROLE, defaultAdmin);
        _writeAddresses(initial);
        version = 1;
        emit AddressesUpdated(1, initial);
    }

    /// @notice Replace the entire address set in one transaction.
    function setAddresses(
        Addresses calldata config
    ) external onlyRole(ADDRESS_MANAGER_ROLE) {
        _writeAddresses(config);
        unchecked {
            version += 1;
        }
        emit AddressesUpdated(version, config);
    }

    /// @notice Batch read for off-chain indexers / multicall-friendly snapshots.
    function getAddresses() external view returns (Addresses memory) {
        return Addresses({
            safe: safe,
            orchestrator: orchestrator,
            registry: registry,
            airlock: airlock,
            poolManager: poolManager,
            positionManager: positionManager,
            tokenFactory: tokenFactory,
            noOpGovernanceFactory: noOpGovernanceFactory,
            stakeRouter: stakeRouter,
            swapRouter: swapRouter,
            limitRouter: limitRouter,
            quoteRouter: quoteRouter,
            airlockWrapper: airlockWrapper,
            deployer: deployer,
            initializer: initializer,
            deploymentForwarder: deploymentForwarder,
            migrator: migrator,
            migratorHook: migratorHook,
            migrationForwarder: migrationForwarder,
            recycler: recycler,
            discontinuationForwarder: discontinuationForwarder,
            nftStorageFactory: nftStorageFactory,
            nftStorageBeacon: nftStorageBeacon,
            vaultFactory: vaultFactory,
            treasury: treasury,
            vaultBeacon: vaultBeacon,
            vaultTokenFactory: vaultTokenFactory,
            squadCheck: squadCheck,
            pbrForwarder: pbrForwarder,
            eth: eth,
            usdc: usdc
        });
    }

    function _writeAddresses(
        Addresses memory config
    ) private {
        safe = config.safe;
        orchestrator = config.orchestrator;
        registry = config.registry;
        airlock = config.airlock;
        poolManager = config.poolManager;
        positionManager = config.positionManager;
        tokenFactory = config.tokenFactory;
        noOpGovernanceFactory = config.noOpGovernanceFactory;
        stakeRouter = config.stakeRouter;
        swapRouter = config.swapRouter;
        limitRouter = config.limitRouter;
        quoteRouter = config.quoteRouter;
        airlockWrapper = config.airlockWrapper;
        deployer = config.deployer;
        initializer = config.initializer;
        deploymentForwarder = config.deploymentForwarder;
        migrator = config.migrator;
        migratorHook = config.migratorHook;
        migrationForwarder = config.migrationForwarder;
        recycler = config.recycler;
        discontinuationForwarder = config.discontinuationForwarder;
        nftStorageFactory = config.nftStorageFactory;
        nftStorageBeacon = config.nftStorageBeacon;
        vaultFactory = config.vaultFactory;
        treasury = config.treasury;
        vaultBeacon = config.vaultBeacon;
        vaultTokenFactory = config.vaultTokenFactory;
        squadCheck = config.squadCheck;
        pbrForwarder = config.pbrForwarder;
        eth = config.eth;
        usdc = config.usdc;
    }
}
