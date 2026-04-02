// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { CreateParams } from "@markets/types/Types.sol";

interface ITokenFactory {
    function create(uint256 totalSupply, CreateParams calldata createData) external returns (address asset, bytes32 salt);
}
