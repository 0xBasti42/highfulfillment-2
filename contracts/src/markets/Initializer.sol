// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { ImmutableAddressProvider } from "@base/ImmutableAddressProvider.sol";
import { ImmutableAirlock } from "@base/ImmutableAirlock.sol";
import { HP20 } from "@markets/tokens/HP20.sol";
import { ITokenFactory } from "@markets/factories/interfaces/ITokenFactory.sol";
import { IDopplerFactory } from "@markets/factories/interfaces/IDopplerFactory.sol";
import { DopplerHook } from "@markets/hooks/DopplerHook.sol";
import { IHooks, IPoolManager, PoolKey } from "@v4-core/PoolManager.sol";
import { ERC20, SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { SafeTransferLib as SoladySafeTransferLib } from "@solady/utils/SafeTransferLib.sol";
import { LPFeeLibrary } from "@v4-core/libraries/LPFeeLibrary.sol";
import { TickMath } from "@v4-core/libraries/TickMath.sol";
import { Currency, CurrencyLibrary } from "@v4-core/types/Currency.sol";
import { Strings } from "@oz/contracts/utils/Strings.sol";
import { CreateParams, PoolData } from "@markets/types/Types.sol";

/**
 * @title Initializer | HighPotential
 * @dev Player token + bonding pool launch. CREATE2 salt for HP20 is produced by Chainlink Functions (`mineSalt.js`); no calldata salt.
 */
contract Initializer is ImmutableAddressProvider, ImmutableAirlock {
    using CurrencyLibrary for Currency;
    using SoladySafeTransferLib for address;
    using SafeTransferLib for ERC20;

    mapping(address module => ModuleState state) public getModuleState;

    // --------------------------------------------
    //  Config
    // --------------------------------------------

    uint256 constant TOTAL_SUPPLY = 22_000_000 ether;
    uint256 constant NUM_TOKENS_TO_SELL = 12_000_000 ether;

    int24 constant STARTING_TICK = 0;
    int24 constant TICK_SPACING = 60;

    address constant NUMERAIRE = address(0);

    // --------------------------------------------
    //  Events / errors
    // --------------------------------------------

    event Create(address indexed asset, PoolData poolData);

    // --------------------------------------------
    //  Initialization
    // --------------------------------------------

    enum ModuleState {
        NotWhitelisted,
        TokenFactory,
        DopplerFactory,
        Migrator
    }

    constructor(address addressProvider_) ImmutableAirlock(addressProvider_) ImmutableAddressProvider(addressProvider_) {
        setModuleStates();
    }

    // --------------------------------------------
    //  Interface
    // --------------------------------------------

    function launchPools(
        CreateParams calldata createData
    ) external onlyPermitted returns (
        address asset, 
        PoolData memory poolData, 
        uint256 excessAsset
    ) {
        (asset, salt) = _deployToken(createData);
        
        (dopplerHook, poolKey) = _deployDoppler(asset, salt);

        migratorHook = _initializeMigrator(asset);

        HP20(asset).lockActivePoolKey(poolKey);
        
        excessAsset = ERC20(asset).balanceOf(address(this));
        if (excessAsset > 0) {
            address orchestrator_ = getAddress(_addressKey("ORCHESTRATOR"));
            ERC20(asset).safeTransfer(orchestrator_, excessAsset);
        }

        poolData = PoolData({
            numeraire: NUMERAIRE,
            activePool: poolKey,
            hookDoppler: address(dopplerHook),
            hookMigrator: address(migratorHook)
        });

        emit Create(asset, poolData);
        return (asset, poolData, excessAsset);
    }

    function migrateLiquidity(address asset, PoolData memory poolData) external onlyPermitted returns (address asset, PoolData memory poolData) {
        // TODO: implement
    }

    // --------------------------------------------
    //  Launch Functions
    // --------------------------------------------

    function _deployToken(CreateParams memory createData) internal returns (address asset_, bytes32 salt_) {
        address tokenFactory = _getAddress(_addressKey("TOKEN_FACTORY"));
        _validateModuleState(tokenFactory, ModuleState.TokenFactory);
        
        (asset_, salt_) = ITokenFactory(tokenFactory).create(TOTAL_SUPPLY, createData);
    }

    function _deployDoppler(address asset, bytes32 salt) internal returns (address dopplerHook_, PoolKey memory poolKey_) {
        address dopplerFactory = _getAddress(_addressKey("DOPPLER_FACTORY"));
        _validateModuleState(dopplerFactory, ModuleState.DopplerFactory);

        address dopplerHook_ = IDopplerFactory(dopplerFactory).deploy(NUM_TOKENS_TO_SELL, salt);

        bool isToken0 = asset < NUMERAIRE;
        PoolKey memory poolKey_ = PoolKey({
            currency0: isToken0 ? Currency.wrap(asset) : Currency.wrap(NUMERAIRE),
            currency1: isToken0 ? Currency.wrap(NUMERAIRE) : Currency.wrap(asset),
            hooks: IHooks(dopplerHook_),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: TICK_SPACING
        });

        ERC20(asset).safeTransfer(dopplerHook_, NUM_TOKENS_TO_SELL); // is this all we need to do to initialize the pool?

        address poolManager = _getAddress(_addressKey("POOL_MANAGER"));
        IPoolManager(poolManager).initialize(poolKey_, TickMath.getSqrtPriceAtTick(STARTING_TICK));

        return (dopplerHook_, poolKey_);
    }

    function _initializeMigrator(address asset) internal returns (address migratorHook_) {
        address migrator = _getAddress(_addressKey("MIGRATOR"));
        _validateModuleState(migrator, ModuleState.Migrator);

        address migrationPool = migrator.initialize(asset, NUMERAIRE); // needs to be recreated in migrator

        return migrationPool;
    }

    // --------------------------------------------
    //  Migration Functions
    // --------------------------------------------

    function _migrateLiquidity(address asset, PoolData memory poolData) internal returns (address asset_, PoolData memory poolData_) {
        // TODO: implement
        return (asset, poolData);
    }

    // --------------------------------------------
    //  Whitelisting
    // --------------------------------------------
    
    function setModuleStates() internal {
        string[] memory names = new string[](3);
        names[0] = "TOKEN_FACTORY";
        names[1] = "DOPPLER_FACTORY";
        names[2] = "MIGRATOR";
        address[] memory addrs = _getAddresses(_addressKeys(names));

        address[] memory modules = new address[](4);
        modules[0] = address(this);
        modules[1] = addrs[0];
        modules[2] = addrs[1];
        modules[3] = addrs[2];

        ModuleState[] memory states = new ModuleState[](4);
        states[0] = ModuleState.Initializer;
        states[1] = ModuleState.TokenFactory;
        states[2] = ModuleState.DopplerFactory;
        states[3] = ModuleState.Migrator;

        _setModuleStates(modules, states);
    }

    function _setModuleStates(address[] calldata modules, ModuleState[] calldata states) internal pure {
        uint256 length = modules.length;
        if (length != states.length) revert ArrayLengthsMismatch();
        for (uint256 i; i < length; ++i) {
            getModuleState[modules[i]] = states[i];
        }
    }

    function _validateModuleState(address module, ModuleState state) internal view {
        if (getModuleState[module] != state) {
            revert WrongModuleState(module, state, getModuleState[module]);
        }
    }
}
