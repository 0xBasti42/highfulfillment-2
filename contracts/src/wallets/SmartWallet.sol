// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import {IAccount06} from "@account-abstraction/legacy/v06/IAccount06.sol";
import {UserOperation06} from "@account-abstraction/legacy/v06/UserOperation06.sol";
import {Receiver} from "@solady/accounts/Receiver.sol";
import {SignatureCheckerLib} from "@solady/utils/SignatureCheckerLib.sol";
import {UUPSUpgradeable} from "@solady/utils/UUPSUpgradeable.sol";
import {WebAuthn} from "@webauthn-sol/WebAuthn.sol";

import {MultiOwnable} from "./MultiOwnable.sol";
import {UserOperation06Hash} from "./UserOperation06Hash.sol";
import {WalletERC1271} from "./WalletERC1271.sol";

/// @title SmartWallet
/// @notice ERC-4337 v0.6 smart account modeled on Coinbase Smart Wallet: multi-owner (EOA + passkey), ERC-1271, UUPS.
/// @dev EntryPoint v0.6 default below; override `entryPoint()` per-chain if needed.
contract SmartWallet is WalletERC1271, IAccount06, MultiOwnable, UUPSUpgradeable, Receiver {
    struct SignatureWrapper {
        uint256 ownerIndex;
        bytes signatureData;
    }

    struct Call {
        address target;
        uint256 value;
        bytes data;
    }

    /// @dev Upper 192 bits of `UserOperation.nonce` for `executeWithoutChainIdValidation` (Coinbase uses Base chain id).
    uint256 public constant REPLAYABLE_NONCE_KEY = 8453;

    error Initialized();
    error SelectorNotAllowed(bytes4 selector);
    error InvalidNonceKey(uint256 key);
    error InvalidImplementation(address implementation);

    modifier onlyEntryPoint() virtual {
        if (msg.sender != entryPoint()) {
            revert Unauthorized();
        }

        _;
    }

    modifier onlyEntryPointOrOwner() virtual {
        if (msg.sender != entryPoint()) {
            _checkOwner();
        }

        _;
    }

    modifier payPrefund(uint256 missingAccountFunds) virtual {
        _;

        assembly ("memory-safe") {
            if missingAccountFunds {
                pop(call(gas(), caller(), missingAccountFunds, codesize(), 0x00, codesize(), 0x00))
            }
        }
    }

    constructor() {
        bytes[] memory owners = new bytes[](1);
        owners[0] = abi.encode(address(0));
        _initializeOwners(owners);
    }

    function initialize(bytes[] calldata owners) external payable virtual {
        if (nextOwnerIndex() != 0) {
            revert Initialized();
        }

        _initializeOwners(owners);
    }

    function validateUserOp(UserOperation06 calldata userOp, bytes32 userOpHash, uint256 missingAccountFunds)
        external
        virtual
        onlyEntryPoint
        payPrefund(missingAccountFunds)
        returns (uint256 validationData)
    {
        uint256 key = userOp.nonce >> 64;

        if (bytes4(userOp.callData) == this.executeWithoutChainIdValidation.selector) {
            userOpHash = getUserOpHashWithoutChainId(userOp);
            if (key != REPLAYABLE_NONCE_KEY) {
                revert InvalidNonceKey(key);
            }

            bytes[] memory calls = abi.decode(userOp.callData[4:], (bytes[]));
            for (uint256 i; i < calls.length; i++) {
                bytes memory callData = calls[i];
                bytes4 selector = bytes4(callData);

                if (selector == UUPSUpgradeable.upgradeToAndCall.selector) {
                    address newImplementation;
                    assembly ("memory-safe") {
                        newImplementation := mload(add(callData, 36))
                    }
                    if (newImplementation.code.length == 0) revert InvalidImplementation(newImplementation);
                }
            }
        } else {
            if (key == REPLAYABLE_NONCE_KEY) {
                revert InvalidNonceKey(key);
            }
        }

        if (_isValidSignature(userOpHash, userOp.signature)) {
            return 0;
        }

        return 1;
    }

    function executeWithoutChainIdValidation(bytes[] calldata calls) external payable virtual onlyEntryPoint {
        for (uint256 i; i < calls.length; i++) {
            bytes calldata call = calls[i];
            bytes4 selector = bytes4(call);
            if (!canSkipChainIdValidation(selector)) {
                revert SelectorNotAllowed(selector);
            }

            _call(address(this), 0, call);
        }
    }

    function execute(address target, uint256 value, bytes calldata data)
        external
        payable
        virtual
        onlyEntryPointOrOwner
    {
        _call(target, value, data);
    }

    function executeBatch(Call[] calldata calls) external payable virtual onlyEntryPointOrOwner {
        for (uint256 i; i < calls.length; i++) {
            _call(calls[i].target, calls[i].value, calls[i].data);
        }
    }

    function entryPoint() public view virtual returns (address) {
        return 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789;
    }

    function getUserOpHashWithoutChainId(UserOperation06 calldata userOp) public view virtual returns (bytes32) {
        return keccak256(abi.encode(UserOperation06Hash.hash(userOp), entryPoint()));
    }

    function implementation() public view returns (address $) {
        assembly ("memory-safe") {
            $ := sload(_ERC1967_IMPLEMENTATION_SLOT)
        }
    }

    function canSkipChainIdValidation(bytes4 functionSelector) public pure returns (bool) {
        if (
            functionSelector == MultiOwnable.addOwnerPublicKey.selector
                || functionSelector == MultiOwnable.addOwnerAddress.selector
                || functionSelector == MultiOwnable.removeOwnerAtIndex.selector
                || functionSelector == MultiOwnable.removeLastOwner.selector
                || functionSelector == UUPSUpgradeable.upgradeToAndCall.selector
        ) {
            return true;
        }
        return false;
    }

    function _call(address target, uint256 value, bytes memory data) internal {
        (bool success, bytes memory result) = target.call{value: value}(data);
        if (!success) {
            assembly ("memory-safe") {
                revert(add(result, 32), mload(result))
            }
        }
    }

    function _isValidSignature(bytes32 hash, bytes calldata signature)
        internal
        view
        virtual
        override
        returns (bool)
    {
        SignatureWrapper memory sigWrapper = abi.decode(signature, (SignatureWrapper));
        bytes memory ownerBytes = ownerAtIndex(sigWrapper.ownerIndex);

        if (ownerBytes.length == 32) {
            if (uint256(bytes32(ownerBytes)) > type(uint160).max) {
                revert InvalidEthereumAddressOwner(ownerBytes);
            }

            address ownerAddr;
            assembly ("memory-safe") {
                ownerAddr := mload(add(ownerBytes, 32))
            }

            return SignatureCheckerLib.isValidSignatureNow(ownerAddr, hash, sigWrapper.signatureData);
        }

        if (ownerBytes.length == 64) {
            (uint256 x, uint256 y) = abi.decode(ownerBytes, (uint256, uint256));

            WebAuthn.WebAuthnAuth memory auth = abi.decode(sigWrapper.signatureData, (WebAuthn.WebAuthnAuth));

            return WebAuthn.verify({challenge: abi.encode(hash), requireUV: false, webAuthnAuth: auth, x: x, y: y});
        }

        revert InvalidOwnerBytesLength(ownerBytes);
    }

    function _authorizeUpgrade(address) internal view virtual override(UUPSUpgradeable) onlyOwner {}

    function _domainNameAndVersion() internal pure override(WalletERC1271) returns (string memory, string memory) {
        return ("HighPotential Smart Wallet", "1");
    }
}
