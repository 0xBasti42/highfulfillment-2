// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { IPoolManager } from "@v4-core/PoolManager.sol";
import { Doppler } from "@markets/hooks/Doppler.sol";

/**
 * @title DopplerFactory | HighPotential
 * @author Isla Labs (Tom Jarvis | 0xBasti42)
 * @custom:experimental DeFi markets covering EPL, NFL, NBA, and more. | Learn more at https://docs.highpotential.io/
 * @custom:security-contact security@islalabs.co
 */
contract DopplerFactory {
    // These variables are purposely not immutable to avoid hitting the contract size limit
    IPoolManager public poolManager;

    constructor(
        IPoolManager poolManager_
    ) {
        poolManager = poolManager_;
    }

    function deploy(
        uint256 numTokensToSell,
        bytes32 salt,
        bytes calldata data
    ) external returns (Doppler) {
        (
            uint256 minimumProceeds,
            uint256 maximumProceeds,
            uint256 startingTime,
            uint256 endingTime,
            int24 startingTick,
            int24 endingTick,
            uint256 epochLength,
            int24 gamma,
            bool isToken0,
            uint256 numPDSlugs,
            uint24 lpFee,
        ) = abi.decode(
            data, (uint256, uint256, uint256, uint256, int24, int24, uint256, int24, bool, uint256, uint24, int24)
        );

        Doppler doppler = new Doppler{ salt: salt }(
            poolManager,
            numTokensToSell,
            minimumProceeds,
            maximumProceeds,
            startingTime,
            endingTime,
            startingTick,
            endingTick,
            epochLength,
            gamma,
            isToken0,
            numPDSlugs,
            msg.sender,
            lpFee
        );

        return doppler;
    }
}
