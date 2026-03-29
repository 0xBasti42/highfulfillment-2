// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { SafeTransferLib } from "@solady/utils/SafeTransferLib.sol";
import { IHooks, IPoolManager, PoolKey } from "@v4-core/PoolManager.sol";
import { LPFeeLibrary } from "@v4-core/libraries/LPFeeLibrary.sol";
import { TickMath } from "@v4-core/libraries/TickMath.sol";
import { Currency, CurrencyLibrary } from "@v4-core/types/Currency.sol";
import { Doppler } from "@markets/hooks/Doppler.sol";
import { IPoolInitializer } from "@base/interfaces/IPoolInitializer.sol";

/**
 * @title Initializer | HighPotential
 * @author Isla Labs (Tom Jarvis | 0xBasti42)
 * @notice Wrapper for DopplerDeployer
 * @custom:experimental DeFi markets covering EPL, NFL, NBA, and more. | Learn more at https://docs.highpotential.io/
 * @custom:security-contact security@islalabs.co
 */
contract UniswapV4Initializer is IPoolInitializer {
    using CurrencyLibrary for Currency;
    using SafeTransferLib for address;

    // --------------------------------------------
    //  Config
    // --------------------------------------------

    /// @notice Address of the Uniswap V4 PoolManager
    IPoolManager public immutable poolManager;

    /// @notice Address of the DopplerDeployer contract
    DopplerDeployer public immutable deployer;

    // --------------------------------------------
    //  Events and Errors
    // --------------------------------------------

    error InvalidTokenOrder();

    // --------------------------------------------
    //  Initialization
    // --------------------------------------------

    /**
     * @param airlock_ Address of the Airlock contract
     * @param poolManager_ Address of the Uniswap V4 PoolManager
     * @param deployer_ Address of the DopplerDeployer contract
     */
    constructor(
        address airlock_,
        IPoolManager poolManager_,
        DopplerDeployer deployer_
    ) ImmutableAirlock(airlock_) {
        poolManager = poolManager_;
        deployer = deployer_;
    }

    // --------------------------------------------
    //  Pool Management
    // --------------------------------------------

    /// @inheritdoc IPoolInitializer
    function initialize(
        address asset,
        address numeraire,
        uint256 numTokensToSell,
        bytes32 salt,
        bytes calldata data
    ) external onlyAirlock returns (address) {
        (,,,, int24 startingTick,,,, bool isToken0,,, int24 tickSpacing) = abi.decode(
            data, (uint256, uint256, uint256, uint256, int24, int24, uint256, int24, bool, uint256, uint24, int24)
        );

        Doppler doppler = deployer.deploy(numTokensToSell, salt, data);

        if (isToken0 && asset > numeraire || !isToken0 && asset < numeraire) {
            revert InvalidTokenOrder();
        }

        PoolKey memory poolKey = PoolKey({
            currency0: isToken0 ? Currency.wrap(asset) : Currency.wrap(numeraire),
            currency1: isToken0 ? Currency.wrap(numeraire) : Currency.wrap(asset),
            hooks: IHooks(doppler),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: tickSpacing
        });

        address(asset).safeTransferFrom(address(airlock), address(doppler), numTokensToSell);

        poolManager.initialize(poolKey, TickMath.getSqrtPriceAtTick(startingTick));

        emit Create(address(doppler), asset, numeraire);

        return address(doppler);
    }

    /// @inheritdoc IPoolInitializer
    function exitLiquidity(
        address hook
    )
        external
        onlyAirlock
        returns (
            uint160 sqrtPriceX96,
            address token0,
            uint128 fees0,
            uint128 balance0,
            address token1,
            uint128 fees1,
            uint128 balance1
        )
    {
        (sqrtPriceX96, token0, fees0, balance0, token1, fees1, balance1) =
            Doppler(payable(hook)).migrate(address(airlock));
    }
}
