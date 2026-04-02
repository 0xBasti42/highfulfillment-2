// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { ImmutableAddressProvider } from "@base/ImmutableAddressProvider.sol";
import { IPoolManager } from "@v4-core/PoolManager.sol";
import { DopplerHook } from "@markets/hooks/DopplerHook.sol";

/**
 * @title DopplerFactory | HighPotential
 * @author Isla Labs (Tom Jarvis | 0xBasti42)
 * @notice Standalone CREATE2 deployer for the canonical bonding curve (same encoding as `Initializer` + `DopplerDeployer`)
 * @custom:experimental DeFi markets covering EPL, NFL, NBA, and more. | Learn more at https://docs.highpotential.io/
 * @custom:security-contact security@islalabs.co
 */
contract DopplerFactory is ImmutableAddressProvider {
    IPoolManager public poolManager;

    uint256 constant MINIMUM_PROCEEDS = 0;
    uint256 constant MAXIMUM_PROCEEDS = 0;
    uint256 constant STARTING_TIME = 0;
    uint256 constant ENDING_TIME = 0;
    int24 constant STARTING_TICK = 0;
    int24 constant ENDING_TICK = 0;
    uint256 constant EPOCH_LENGTH = 0;
    int24 constant GAMMA = 1e18;
    bool constant IS_TOKEN0 = false;
    uint256 constant NUM_PD_SLUGS = 0;
    uint24 constant LP_FEE = 1e18;

    constructor(IPoolManager poolManager_) {
        poolManager = poolManager_;
    }

    function deploy(uint256 numTokensToSell, bytes32 salt) external returns (address dopplerHook) {
        DopplerHook dopplerHook = new DopplerHook{ salt: salt }(
            poolManager,
            numTokensToSell,
            MINIMUM_PROCEEDS,
            MAXIMUM_PROCEEDS,
            STARTING_TIME,
            ENDING_TIME,
            STARTING_TICK,
            ENDING_TICK,
            EPOCH_LENGTH,
            GAMMA,
            IS_TOKEN0,
            NUM_PD_SLUGS,
            getAddress(_addressKey("INITIALIZER")),
            LP_FEE
        );

        return address(dopplerHook);
    }
}
