// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import {UserOperation06} from "@account-abstraction/legacy/v06/UserOperation06.sol";

/// @notice v0.6 `UserOperation` inner hash (matches EntryPoint v0.6 `getUserOpHash` before chain id).
/// @dev Mirrors eth-infinitism/account-abstraction v0.6 `UserOperationLib.hash`.
library UserOperation06Hash {
    function _calldataKeccak(bytes calldata data) private pure returns (bytes32 ret) {
        assembly ("memory-safe") {
            let mem := mload(0x40)
            let len := data.length
            calldatacopy(mem, data.offset, len)
            ret := keccak256(mem, len)
        }
    }

    function hash(UserOperation06 calldata userOp) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                userOp.sender,
                userOp.nonce,
                _calldataKeccak(userOp.initCode),
                _calldataKeccak(userOp.callData),
                userOp.callGasLimit,
                userOp.verificationGasLimit,
                userOp.preVerificationGas,
                userOp.maxFeePerGas,
                userOp.maxPriorityFeePerGas,
                _calldataKeccak(userOp.paymasterAndData)
            )
        );
    }
}
