// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import {LibClone} from "@solady/utils/LibClone.sol";

import {SmartWallet} from "./SmartWallet.sol";

/// @title AAFactory
/// @notice CREATE2 ERC-1967 proxy factory for `SmartWallet` (Coinbase-style account factory).
contract AAFactory {
    address public immutable implementation;

    event AccountCreated(address indexed account, bytes[] owners, uint256 nonce);

    error ImplementationUndeployed();
    error OwnerRequired();

    constructor(address implementation_) payable {
        if (implementation_.code.length == 0) revert ImplementationUndeployed();
        implementation = implementation_;
    }

    function createAccount(bytes[] calldata owners, uint256 nonce)
        external
        payable
        virtual
        returns (SmartWallet account)
    {
        if (owners.length == 0) {
            revert OwnerRequired();
        }

        (bool alreadyDeployed, address accountAddress) =
            LibClone.createDeterministicERC1967(msg.value, implementation, _getSalt(owners, nonce));

        account = SmartWallet(payable(accountAddress));

        if (!alreadyDeployed) {
            emit AccountCreated(address(account), owners, nonce);
            account.initialize(owners);
        }
    }

    function getAddress(bytes[] calldata owners, uint256 nonce) external view returns (address) {
        return LibClone.predictDeterministicAddress(initCodeHash(), _getSalt(owners, nonce), address(this));
    }

    function initCodeHash() public view virtual returns (bytes32) {
        return LibClone.initCodeHashERC1967(implementation);
    }

    function _getSalt(bytes[] calldata owners, uint256 nonce) internal pure returns (bytes32) {
        return keccak256(abi.encode(owners, nonce));
    }
}
