// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import { CreateParams, PoolData } from "@core/types/AssetTypes.sol";

interface IInitializer {
    function deploy(CreateParams calldata createData) external returns (address asset, PoolData memory poolData, uint256 excessAsset);
}
