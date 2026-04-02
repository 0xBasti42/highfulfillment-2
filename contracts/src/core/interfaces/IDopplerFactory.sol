// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

interface IDopplerFactory {
    function deploy(bytes32 salt) external returns (address dopplerHook);
}