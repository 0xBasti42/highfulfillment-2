// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import { PoolData } from "@markets/types/Types.sol";

library Events {
    event Create(address indexed asset, PoolData poolData);
    event Migrate(address indexed asset, PoolData poolData);
}