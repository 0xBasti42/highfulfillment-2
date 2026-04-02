// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { ImmutableAddressProvider } from "@base/ImmutableAddressProvider.sol";
import { PoolData } from "@markets/types/Types.sol";

contract Orchestrator is ImmutableAddressProvider {
    constructor(address addressProvider_) ImmutableAddressProvider(addressProvider_) { }

    function initializePool(address asset, PoolData memory poolData) external {
        // TODO: implement
    }

    function completeLaunch(address asset, PoolData memory poolData) external onlyInitializer {
        // TODO: implement
    }
}
