// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { AddressBook } from "@base/AddressBook.sol";
import { IPoolManager } from "@v4-core/PoolManager.sol";
import { DopplerHook } from "@markets/hooks/DopplerHook.sol";
import { DopplerConfig } from "@markets/libraries/DopplerConfig.sol";

contract DopplerFactory is AddressBook {
    constructor(address addressProvider_) AddressBook(addressProvider_) { }

    function deploy(uint256 numTokensToSell, bytes32 salt) external returns (address dopplerHook) {
        DopplerHook dopplerHook = new DopplerHook{ salt: salt }(
            _getAddress(_addressKey("POOL_MANAGER")),
            numTokensToSell,
            DopplerConfig.MINIMUM_PROCEEDS,
            DopplerConfig.MAXIMUM_PROCEEDS,
            DopplerConfig.STARTING_TIME,
            DopplerConfig.ENDING_TIME,
            DopplerConfig.STARTING_TICK,
            DopplerConfig.ENDING_TICK,
            DopplerConfig.EPOCH_LENGTH,
            DopplerConfig.GAMMA,
            DopplerConfig.IS_TOKEN0,
            DopplerConfig.NUM_PD_SLUGS,
            getAddress(_addressKey("INITIALIZER")),
            DopplerConfig.LP_FEE
        );

        return address(dopplerHook);
    }
}
