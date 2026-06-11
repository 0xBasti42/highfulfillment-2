// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { LibClone } from "@solady/utils/LibClone.sol";

import { AddressBook } from "@core/AddressBook.sol";

import { HPSmartWallet } from "./HPSmartWallet.sol";
import { MultiOwnable } from "./base/MultiOwnable.sol";
import { IHPWalletFactory } from "./interfaces/IHPWalletFactory.sol";
import { OwnerValidation } from "./libraries/OwnerValidation.sol";

/// @title HPSmartWalletFactory
/// @notice CREATE2 ERC-1967 proxy factory for `HPSmartWallet` (Coinbase-style account factory). It is also the
///         authoritative wallet-legitimacy oracle: every wallet it deploys is flagged in `isHPWallet`, keyed by
///         the unforgeable CREATE2 address. The paymaster reads that flag to decide what to sponsor.
/// @dev There is deliberately no owner -> wallet registry. Owner-to-wallet discovery is handled off-chain by
///      Turnkey (which manages the signer and the deterministic wallet address), and enumeration/analytics are
///      handled by indexing the `AccountCreated` event. This removes the unauthenticated, globally-exclusive
///      owner indexing that previously allowed registry poisoning and counterfactual-address squatting.
contract HPSmartWalletFactory is AddressBook, IHPWalletFactory {
    address public immutable implementation;

    /// @notice Wallet-keyed legitimacy flag. Keyed by the CREATE2 address, so it cannot be poisoned by
    ///         attacker-chosen owner bytes. Read by `HPPaymaster` during validation (sender-associated storage).
    mapping(address wallet => bool) public isHPWallet;

    /// @dev Deployment order. Enumeration only; prefer indexing `AccountCreated` off-chain for large sets.
    address[] private _wallets;

    event AccountCreated(address indexed account, bytes[] owners, uint256 nonce);

    error ImplementationUndeployed();
    error OwnerRequired();

    constructor(address implementation_, address addressProvider_) payable AddressBook(addressProvider_) {
        if (implementation_.code.length == 0) revert ImplementationUndeployed();
        implementation = implementation_;
    }

    /// @notice Deploys (or returns) the deterministic wallet for `owners` + `nonce` and flags it as an HP wallet.
    /// @dev Idempotent: an already-deployed wallet is returned without re-initialization or re-flagging. The salt
    ///      covers only owners + nonce, so user settings cannot influence the counterfactual address.
    function createAccount(bytes[] calldata owners, uint256 nonce)
        external
        payable
        virtual
        returns (HPSmartWallet account)
    {
        _validateOwners(owners);

        (bool alreadyDeployed, address accountAddress) =
            LibClone.createDeterministicERC1967(msg.value, implementation, _getSalt(owners, nonce));

        account = HPSmartWallet(payable(accountAddress));

        if (!alreadyDeployed) {
            account.initialize(owners);
            isHPWallet[accountAddress] = true;
            _wallets.push(accountAddress);
            emit AccountCreated(accountAddress, owners, nonce);
        }
    }

    /// @notice Counterfactual wallet address for `owners` + `nonce` (used by the client and Turnkey config).
    /// @dev Validates `owners` with the same rules as deployment, so a predicted address is always deployable
    ///      (no advertising of addresses that `createAccount` would reject, which could trap pre-funded ETH).
    function getAddress(bytes[] calldata owners, uint256 nonce) external view returns (address) {
        _validateOwners(owners);
        return LibClone.predictDeterministicAddress(initCodeHash(), _getSalt(owners, nonce), address(this));
    }

    function initCodeHash() public view virtual returns (bytes32) {
        return LibClone.initCodeHashERC1967(implementation);
    }

    // --------------------------------------------
    //  Enumeration
    // --------------------------------------------

    function walletCount() external view returns (uint256) {
        return _wallets.length;
    }

    function walletAt(uint256 index) external view returns (address) {
        return _wallets[index];
    }

    /// @notice Paginated read — prefer this (or off-chain `AccountCreated` indexing) for large sets.
    function getWallets(uint256 offset, uint256 limit) external view returns (address[] memory) {
        return _getWalletsSlice(offset, limit);
    }

    function getAllWallets() external view returns (address[] memory) {
        return _getWalletsSlice(0, _wallets.length);
    }

    function _getWalletsSlice(uint256 offset, uint256 limit) private view returns (address[] memory wallets) {
        uint256 n = _wallets.length;
        if (offset >= n || limit == 0) {
            return new address[](0);
        }
        uint256 end = offset + limit;
        if (end > n) end = n;
        uint256 len = end - offset;
        wallets = new address[](len);
        for (uint256 i; i < len; ++i) {
            wallets[i] = _wallets[offset + i];
        }
    }

    /// @dev Mirrors deployment-time owner validation: non-empty, each owner controllable, no duplicates. Keeps
    ///      counterfactual prediction and deployment in lockstep so funds are never sent to an undeployable
    ///      address. Note `OwnerValidation` cannot reject the (unknowable here) future wallet's own address as an
    ///      owner; that self-owner case is caught at deployment by `MultiOwnable._addOwnerAtIndex`.
    function _validateOwners(bytes[] calldata owners) internal pure {
        if (owners.length == 0) revert OwnerRequired();

        for (uint256 i; i < owners.length; ++i) {
            OwnerValidation.validate(owners[i]);

            bytes32 ownerHash = keccak256(owners[i]);
            for (uint256 j; j < i; ++j) {
                if (ownerHash == keccak256(owners[j])) revert MultiOwnable.AlreadyOwner(owners[i]);
            }
        }
    }

    function _getSalt(bytes[] calldata owners, uint256 nonce) internal pure returns (bytes32) {
        return keccak256(abi.encode(owners, nonce));
    }
}
