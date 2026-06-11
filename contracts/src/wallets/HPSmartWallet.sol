// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { IAccount06 } from "@account-abstraction/legacy/v06/IAccount06.sol";
import { UserOperation06 } from "@account-abstraction/legacy/v06/UserOperation06.sol";
import { Receiver } from "@solady/accounts/Receiver.sol";
import { SignatureCheckerLib } from "@solady/utils/SignatureCheckerLib.sol";
import { UUPSUpgradeable } from "@solady/utils/UUPSUpgradeable.sol";
import { WebAuthn } from "@webauthn-sol/WebAuthn.sol";

import { AddressBook } from "@core/AddressBook.sol";

import { DefaultCrypto, DefaultStablecoin } from "./types/HPWalletTypes.sol";
import { MultiOwnable } from "./base/MultiOwnable.sol";
import { UserOperation06Hash } from "./base/UserOperation06Hash.sol";
import { WalletERC1271 } from "./base/WalletERC1271.sol";

/// @notice Storage layout used by this contract.
/// @custom:storage-location erc7201:highpotential.storage.WalletSettings
struct WalletSettingsStorage {
    DefaultCrypto defaultCrypto;
    DefaultStablecoin defaultStablecoin;
}

/// @notice User-specific manager contracts, co-located in the wallet (authoritative; no central registry).
/// @dev Read by the frontend in a single `eth_call` via `accountSet()`. Populated by an owner post-creation
///      (or by a future factory orchestration self-call once PositionManager/VaultManager are designed); not an
///      `initialize` arg, so it cannot influence the counterfactual address.
/// @custom:storage-location erc7201:highpotential.storage.AccountSet
struct AccountSetStorage {
    address positionManager;
    address vaultManager;
}

/// @title HPSmartWallet
/// @notice ERC-4337 v0.6 smart account modeled on Coinbase Smart Wallet: multi-owner (EOA + passkey), ERC-1271, UUPS.
/// @dev Extends the base account with user settings (DefaultCrypto / DefaultStablecoin) and the user's AccountSet
///      (PositionManager / VaultManager) in ERC-7201 namespaced storage, plus AddressProvider-based token
///      resolution. Owner -> wallet discovery is handled off-chain by Turnkey; legitimacy is asserted by the
///      factory's `isHPWallet` flag. EntryPoint v0.6 default below; override `entryPoint()` per-chain if needed.
contract HPSmartWallet is WalletERC1271, IAccount06, MultiOwnable, UUPSUpgradeable, Receiver, AddressBook {
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

    /// @dev keccak256(abi.encode(uint256(keccak256("highpotential.storage.WalletSettings")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant _WALLET_SETTINGS_STORAGE_LOCATION =
        0xde9abc39f8ba6496385be7b2e06f782787ee07b9096c13bc6574d61d02346900;
    /// @dev keccak256(abi.encode(uint256(keccak256("highpotential.storage.AccountSet")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant _ACCOUNT_SET_STORAGE_LOCATION =
        0xd2d10004138f2882870e52b168c3ad025ba8daea9d7df73d3caa86e3d34a7b00;

    event DefaultCryptoUpdated(DefaultCrypto indexed previous, DefaultCrypto indexed current);
    event DefaultStablecoinUpdated(DefaultStablecoin indexed previous, DefaultStablecoin indexed current);
    event AccountSetUpdated(address indexed positionManager, address indexed vaultManager);

    error Initialized();
    error SelectorNotAllowed(bytes4 selector);
    error InvalidNonceKey(uint256 key);
    error InvalidImplementation(address implementation);

    modifier onlyEntryPoint() {
        if (msg.sender != entryPoint()) {
            revert Unauthorized();
        }

        _;
    }

    modifier onlyEntryPointOrOwner() {
        if (msg.sender != entryPoint()) {
            _checkOwner();
        }

        _;
    }

    modifier payPrefund(uint256 missingAccountFunds) {
        _;

        assembly ("memory-safe") {
            if missingAccountFunds {
                pop(call(gas(), caller(), missingAccountFunds, codesize(), 0x00, codesize(), 0x00))
            }
        }
    }

    constructor(address addressProvider_) AddressBook(addressProvider_) {
        bytes[] memory owners = new bytes[](1);
        owners[0] = abi.encode(address(0));
        _initializeOwners(owners);
    }

    function initialize(bytes[] calldata owners) external payable virtual {
        if (nextOwnerIndex() != 0) {
            revert Initialized();
        }

        _initializeOwners(owners);

        // Seed user settings to platform defaults (mirrors the UI defaults); the user can update them post-creation.
        // Deliberately not initializer args: the counterfactual address must depend only on owners + nonce, and a
        // front-runner of `createAccount` must not be able to influence wallet state.
        // Previous values are the enum zero values (BTC / TGBP) — the actual pre-init state — so off-chain
        // indexers reconstructing preference history see the correct transition.
        WalletSettingsStorage storage $ = _getWalletSettingsStorage();
        $.defaultCrypto = DefaultCrypto.ETH;
        $.defaultStablecoin = DefaultStablecoin.TGBP;
        emit DefaultCryptoUpdated(DefaultCrypto.BTC, DefaultCrypto.ETH);
        emit DefaultStablecoinUpdated(DefaultStablecoin.TGBP, DefaultStablecoin.TGBP);
    }

    // --------------------------------------------
    //  User settings
    // --------------------------------------------

    /// @notice Updates the preferred crypto asset. Callable by an owner directly or via EntryPoint `execute` self-call.
    function setDefaultCrypto(DefaultCrypto newDefaultCrypto) external virtual onlyOwner {
        WalletSettingsStorage storage $ = _getWalletSettingsStorage();
        DefaultCrypto previous = $.defaultCrypto;
        $.defaultCrypto = newDefaultCrypto;
        emit DefaultCryptoUpdated(previous, newDefaultCrypto);
    }

    /// @notice Updates the preferred stablecoin. Callable by an owner directly or via EntryPoint `execute` self-call.
    function setDefaultStablecoin(DefaultStablecoin newDefaultStablecoin) external virtual onlyOwner {
        WalletSettingsStorage storage $ = _getWalletSettingsStorage();
        DefaultStablecoin previous = $.defaultStablecoin;
        $.defaultStablecoin = newDefaultStablecoin;
        emit DefaultStablecoinUpdated(previous, newDefaultStablecoin);
    }

    function defaultCrypto() public view virtual returns (DefaultCrypto) {
        return _getWalletSettingsStorage().defaultCrypto;
    }

    function defaultStablecoin() public view virtual returns (DefaultStablecoin) {
        return _getWalletSettingsStorage().defaultStablecoin;
    }

    /// @notice Both settings in a single call (one cheap read for the UI).
    function walletSettings() external view virtual returns (DefaultCrypto, DefaultStablecoin) {
        WalletSettingsStorage storage $ = _getWalletSettingsStorage();
        return ($.defaultCrypto, $.defaultStablecoin);
    }

    /// @notice Token address for the preferred crypto, resolved via `AddressProvider`.
    /// @dev Reverts `AddressNotFound` while the key is unset (e.g. SETH before its wrapper is deployed).
    function defaultCryptoAddress() external view virtual returns (address) {
        return _getAddress(_addressKey(_cryptoKeyName(defaultCrypto())));
    }

    /// @notice Token address for the preferred stablecoin, resolved via `AddressProvider`.
    function defaultStablecoinAddress() external view virtual returns (address) {
        return _getAddress(_addressKey(_stablecoinKeyName(defaultStablecoin())));
    }

    function _cryptoKeyName(DefaultCrypto crypto) internal pure returns (string memory) {
        if (crypto == DefaultCrypto.BTC) return "CBBTC";
        if (crypto == DefaultCrypto.ETH) return "WETH";
        return "SETH";
    }

    function _stablecoinKeyName(DefaultStablecoin stablecoin) internal pure returns (string memory) {
        if (stablecoin == DefaultStablecoin.TGBP) return "TGBP";
        if (stablecoin == DefaultStablecoin.USDC) return "USDC";
        if (stablecoin == DefaultStablecoin.EURC) return "EURC";
        return "DAI";
    }

    function _getWalletSettingsStorage() internal pure returns (WalletSettingsStorage storage $) {
        assembly ("memory-safe") {
            $.slot := _WALLET_SETTINGS_STORAGE_LOCATION
        }
    }

    // --------------------------------------------
    //  Account set (user-specific managers)
    // --------------------------------------------

    /// @notice The user's PositionManager and VaultManager, in a single cheap read for the UI.
    function accountSet() external view virtual returns (address positionManager, address vaultManager) {
        AccountSetStorage storage $ = _getAccountSetStorage();
        return ($.positionManager, $.vaultManager);
    }

    /// @notice Sets the user's manager contracts. Callable by an owner directly or via EntryPoint `execute`
    ///         self-call.
    function setAccountSet(address positionManager, address vaultManager) external virtual onlyOwner {
        AccountSetStorage storage $ = _getAccountSetStorage();
        $.positionManager = positionManager;
        $.vaultManager = vaultManager;
        emit AccountSetUpdated(positionManager, vaultManager);
    }

    function _getAccountSetStorage() internal pure returns (AccountSetStorage storage $) {
        assembly ("memory-safe") {
            $.slot := _ACCOUNT_SET_STORAGE_LOCATION
        }
    }

    // --------------------------------------------
    //  ERC-4337
    // --------------------------------------------

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
                || functionSelector == UUPSUpgradeable.upgradeToAndCall.selector
        ) {
            return true;
        }
        return false;
    }

    function _call(address target, uint256 value, bytes memory data) internal {
        (bool success, bytes memory result) = target.call{ value: value }(data);
        if (!success) {
            assembly ("memory-safe") {
                revert(add(result, 32), mload(result))
            }
        }
    }

    /// @notice ERC-1271 verification that always returns a selector, never reverts.
    /// @dev Routes signature parsing through a self-`staticcall` so malformed signature blobs, stale/out-of-range
    ///      owner indices, and malformed WebAuthn payloads surface as `0xffffffff` rather than a revert, honoring
    ///      the ERC-1271 contract that failure is reported via the return value.
    function isValidSignature(bytes32 hash, bytes calldata signature)
        public
        view
        virtual
        override
        returns (bytes4)
    {
        try this.isValidSignatureExternal(replaySafeHash(hash), signature) returns (bool ok) {
            return ok ? bytes4(0x1626ba7e) : bytes4(0xffffffff);
        } catch {
            return 0xffffffff;
        }
    }

    /// @notice Self-only external wrapper enabling the `try/catch` in `isValidSignature`.
    /// @dev `replaySafeHash` is already applied by the caller; do not re-wrap.
    function isValidSignatureExternal(bytes32 replaySafeHash_, bytes calldata signature)
        external
        view
        virtual
        returns (bool)
    {
        if (msg.sender != address(this)) revert Unauthorized();
        return _isValidSignature(replaySafeHash_, signature);
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

        // Out-of-range or removed owner index: report failure rather than reverting.
        if (ownerBytes.length == 0) {
            return false;
        }

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

            return WebAuthn.verify({ challenge: abi.encode(hash), requireUV: false, webAuthnAuth: auth, x: x, y: y });
        }

        revert InvalidOwnerBytesLength(ownerBytes);
    }

    function _authorizeUpgrade(address) internal view virtual override(UUPSUpgradeable) onlyOwner { }

    function _domainNameAndVersion() internal pure override(WalletERC1271) returns (string memory, string memory) {
        return ("HighPotential Smart Wallet", "1");
    }
}
