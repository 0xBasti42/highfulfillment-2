// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import { CreateParams } from "@core/types/Types.sol";

interface ITokenFactory {
    function create(uint256 totalSupply, CreateParams calldata createData) external returns (address asset, bytes32 salt);
}
