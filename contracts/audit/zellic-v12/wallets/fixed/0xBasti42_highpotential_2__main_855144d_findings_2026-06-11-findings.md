# Audited by [V12](https://v12.sh/)

The only autonomous auditor that finds critical bugs. Not all audits are equal, so stop paying for bad ones. Just use V12. No calls, demos, or intros.

# Uncontrollable owner entries can permanently brick the wallet
**#85733**
- Severity: Critical
- Validity: Unreviewed

## Source locations

### `contracts/src/wallets/HPSmartWallet.sol` (2 locations)
#### Lines 104-109 — _Initializer forwards the supplied owner list into inherited owner storage without local reachability checks._

```
    function initialize(bytes[] calldata owners) external payable virtual {
        if (nextOwnerIndex() != 0) {
            revert Initialized();
        }

        _initializeOwners(owners);
```

⋯
#### Lines 349-382 — _Account signature validation relies on the stored owner entry, so an inert final owner cannot authorize EntryPoint execution._

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
        }

        if (ownerBytes.length == 64) {
            (uint256 x, uint256 y) = abi.decode(ownerBytes, (uint256, uint256));

            WebAuthn.WebAuthnAuth memory auth = abi.decode(sigWrapper.signatureData, (WebAuthn.WebAuthnAuth));

            return WebAuthn.verify({ challenge: abi.encode(hash), requireUV: false, webAuthnAuth: auth, x: x, y: y });
```

### `contracts/src/wallets/base/MultiOwnable.sol` (5 locations)
#### Lines 36-53 — _Owner addition accepts arbitrary addresses and final-owner removal guard counts entries rather than reachable controllers._ — _Owner-addition entrypoints accept the supplied address or public key and immediately add it._ — _The final-owner guard checks only the pre-removal owner count._

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
    }
```

⋯
#### Lines 75-78 — _`ownerCount()` counts stored entries, not controllable owners._

```
    function ownerCount() public view virtual returns (uint256) {
        MultiOwnableStorage storage $ = _getMultiOwnableStorage();
        return $.nextOwnerIndex - $.removedOwnersCount;
    }
```

⋯
#### Lines 84-98 — _Initial owner validation checks only byte length and address upper bits, accepting address(0)._

```
    function _initializeOwners(bytes[] memory owners) internal virtual {
        MultiOwnableStorage storage $ = _getMultiOwnableStorage();
        uint256 nextOwnerIndex_ = $.nextOwnerIndex;
        for (uint256 i; i < owners.length; i++) {
            if (owners[i].length != 32 && owners[i].length != 64) {
                revert InvalidOwnerBytesLength(owners[i]);
            }

            if (owners[i].length == 32 && uint256(bytes32(owners[i])) > type(uint160).max) {
                revert InvalidEthereumAddressOwner(owners[i]);
            }

            _addOwnerAtIndex(owners[i], nextOwnerIndex_++);
        }
        $.nextOwnerIndex = nextOwnerIndex_;
```

⋯
#### Lines 101-108 — _`_addOwnerAtIndex()` stores any non-duplicate owner bytes supplied by the caller._

```
    function _addOwnerAtIndex(bytes memory owner, uint256 index) internal virtual {
        if (isOwnerBytes(owner)) revert AlreadyOwner(owner);

        MultiOwnableStorage storage $ = _getMultiOwnableStorage();
        $.isOwner[owner] = true;
        $.ownerAtIndex[index] = owner;

        emit AddOwner(index, owner);
```

⋯
#### Lines 126-132 — _Owner authorization requires a caller matching an owner address or a wallet self-call, leaving zero/self-only owner sets unable to initiate control._

```
    function _checkOwner() internal view virtual {
        if (isOwnerAddress(msg.sender) || (msg.sender == address(this))) {
            return;
        }

        revert Unauthorized();
    }
```

## Description

The wallet treats any correctly shaped owner encoding as a valid controller, even when that entry cannot actually initiate calls or produce usable signatures. During `initialize`, `_initializeOwners` accepts arbitrary `32`-byte address encodings such as `abi.encode(address(0))`, and ongoing owner management similarly lets an authorized owner add arbitrary addresses or unusable P-256 key material through `addOwnerAddress` and `addOwnerPublicKey`. The final-owner protection in `removeOwnerAtIndex` only checks `ownerCount()`, which is a count of stored entries rather than reachable controllers. As a result, a wallet can be left with one recorded owner that cannot satisfy `_checkOwner` and cannot pass `_isValidSignature`, while the code still believes the invariant of having a remaining controller is preserved. This breaks the intended liveness guarantee behind the last-owner guard and makes the owner set effectively empty even though storage still contains an owner record.

## Root cause

`MultiOwnable` uses raw stored owner entries as a proxy for controllable owners and does not validate that newly added or initialized owner bytes correspond to a reachable authorization mechanism.

## Impact

A malicious or compromised owner, or a malicious initialization flow that installs inert owners, can permanently strand the wallet with no reachable controller. Once that happens, `execute`, owner management, upgrades, and signature-based EntryPoint operations become unreachable, so ETH, tokens, NFTs, and administrative authority held by the wallet can remain permanently frozen.

## Proof of concept

### Test case

```
// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { UserOperation06 } from "@account-abstraction/legacy/v06/UserOperation06.sol";

import { HPSmartWallet } from "@src/wallets/HPSmartWallet.sol";
import { MultiOwnable } from "@src/wallets/base/MultiOwnable.sol";

import { WalletTestBase } from "./WalletTestBase.sol";

contract WalletHarnessPlaceholderTest is WalletTestBase {
    function test_poc_zeroAddressOwnerCanBrickWalletAndFreezeAssets() public {
        HPSmartWallet wallet = _createWallet(ownerEOA, 0);
        address recipient = makeAddr("recipient");
        address recoveryOwner = makeAddr("recoveryOwner");

        vm.deal(address(wallet), 1 ether);

        vm.startPrank(ownerEOA);
        wallet.addOwnerAddress(address(0));
        wallet.removeOwnerAtIndex(0, abi.encode(ownerEOA));
        vm.stopPrank();

        assertEq(wallet.ownerCount(), 1);
        assertTrue(wallet.isOwnerAddress(address(0)));
        assertFalse(wallet.isOwnerAddress(ownerEOA));
        assertEq(address(wallet).balance, 1 ether);

        vm.prank(ownerEOA);
        vm.expectRevert(MultiOwnable.Unauthorized.selector);
        wallet.execute(recipient, 1 ether, "");

        vm.prank(ownerEOA);
        vm.expectRevert(MultiOwnable.Unauthorized.selector);
        wallet.addOwnerAddress(recoveryOwner);

        UserOperation06 memory op = _baseUserOp(address(wallet), 0);
        bytes32 userOpHash = keccak256("withdraw frozen funds");
        op.callData = abi.encodeCall(HPSmartWallet.execute, (recipient, 1 ether, ""));
        op.signature = _eoaSignature(ownerPk, userOpHash, 0);

        vm.prank(entryPointAddr);
        uint256 validationData = wallet.validateUserOp(op, userOpHash, 0);

        assertEq(validationData, 1);
        assertEq(address(wallet).balance, 1 ether);
        assertEq(recipient.balance, 0);
    }
}
```

### Setup script

```
#!/bin/bash
set -e

# install dependencies
cd contracts && rm -rf out cache && forge build
```

### Output

```
[output truncated: 24 lines & 0.9990234375 KB skipped]
84 |     modifier notDelegated() virtual {
   |     ^ (Relevant source part starts here and spans across multiple lines).


Ran 1 test for test/wallets/WalletHarnessPlaceholder.t.sol:WalletHarnessPlaceholderTest
[PASS] test_poc_zeroAddressOwnerCanBrickWalletAndFreezeAssets() (gas: 328492)
Suite result: ok. 1 passed; 0 failed; 0 skipped; finished in 2.37ms (727.52µs CPU time)

Ran 1 test suite in 9.40ms (2.37ms CPU time): 1 tests passed, 0 failed, 0 skipped (1 total tests)
Warning: Found unknown `depth` config key in section `fuzz` defined in foundry.toml.
```

### Considerations

PoC covers the public-entry-point self-brick path via addOwnerAddress(address(0)) followed by removeOwnerAtIndex on the last reachable EOA owner, and verifies frozen ETH plus loss of direct owner calls and EntryPoint signature authorization. It does not exercise the alternate inert-owner variants through initialize(...) or unusable P-256 owner material, though the same storage/counting defect underlies those paths.

## Remediation

### Explanation

Centralized owner validation in MultiOwnable so both initialization and later owner additions reject uncontrollable owners: zero-address/self-address EOA owners and invalid P-256 public keys. Updated the wallet implementation constructor to mark the implementation initialized without storing an invalid sentinel owner, preserving proxy initialization while removing the inert-owner path.

### Patch

```diff
diff --git a/contracts/src/wallets/HPSmartWallet.sol b/contracts/src/wallets/HPSmartWallet.sol
--- a/contracts/src/wallets/HPSmartWallet.sol
+++ b/contracts/src/wallets/HPSmartWallet.sol
@@ -1,393 +1,393 @@
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
-import { MultiOwnable } from "./base/MultiOwnable.sol";
+import { MultiOwnable, MultiOwnableStorage } from "./base/MultiOwnable.sol";
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
-        bytes[] memory owners = new bytes[](1);
-        owners[0] = abi.encode(address(0));
-        _initializeOwners(owners);
+        MultiOwnableStorage storage $ = _getMultiOwnableStorage();
+        $.nextOwnerIndex = 1;
+        $.removedOwnersCount = 1;
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

diff --git a/contracts/src/wallets/base/MultiOwnable.sol b/contracts/src/wallets/base/MultiOwnable.sol
--- a/contracts/src/wallets/base/MultiOwnable.sol
+++ b/contracts/src/wallets/base/MultiOwnable.sol
@@ -1,139 +1,160 @@
 // SPDX-License-Identifier: AGPL-3.0
 pragma solidity ^0.8.34;
 
+import { FCL_Elliptic_ZZ } from "FreshCryptoLib/FCL_elliptic.sol";
+
 /// @notice Storage layout used by this contract.
 /// @custom:storage-location erc7201:coinbase.storage.MultiOwnable
 struct MultiOwnableStorage {
     uint256 nextOwnerIndex;
     uint256 removedOwnersCount;
     mapping(uint256 index => bytes owner) ownerAtIndex;
     mapping(bytes bytes_ => bool isOwner_) isOwner;
 }
 
 /// @title Multi Ownable
 /// @notice Multiple owners as ABI-encoded address (32 bytes) or P-256 public key (64 bytes).
 /// @dev Storage slot matches Coinbase Smart Wallet (constant name typo `MUTLI` preserved).
 contract MultiOwnable {
     bytes32 private constant MUTLI_OWNABLE_STORAGE_LOCATION =
         0x97e2c6aad4ce5d562ebfaa00db6b9e0fb66ea5d8162ed5b243f51a2e03086f00;
 
     error Unauthorized();
     error AlreadyOwner(bytes owner);
     error NoOwnerAtIndex(uint256 index);
     error WrongOwnerAtIndex(uint256 index, bytes expectedOwner, bytes actualOwner);
     error InvalidOwnerBytesLength(bytes owner);
     error InvalidEthereumAddressOwner(bytes owner);
+    error InvalidPublicKeyOwner(bytes owner);
     error LastOwner();
 
     event AddOwner(uint256 indexed index, bytes owner);
     event RemoveOwner(uint256 indexed index, bytes owner);
 
     modifier onlyOwner() {
         _checkOwner();
         _;
     }
 
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
     }
 
     function isOwnerAddress(address account) public view virtual returns (bool) {
         return _getMultiOwnableStorage().isOwner[abi.encode(account)];
     }
 
     function isOwnerPublicKey(bytes32 x, bytes32 y) public view virtual returns (bool) {
         return _getMultiOwnableStorage().isOwner[abi.encode(x, y)];
     }
 
     function isOwnerBytes(bytes memory account) public view virtual returns (bool) {
         return _getMultiOwnableStorage().isOwner[account];
     }
 
     function ownerAtIndex(uint256 index) public view virtual returns (bytes memory) {
         return _getMultiOwnableStorage().ownerAtIndex[index];
     }
 
     function nextOwnerIndex() public view virtual returns (uint256) {
         return _getMultiOwnableStorage().nextOwnerIndex;
     }
 
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
-            if (owners[i].length != 32 && owners[i].length != 64) {
-                revert InvalidOwnerBytesLength(owners[i]);
-            }
-
-            if (owners[i].length == 32 && uint256(bytes32(owners[i])) > type(uint160).max) {
-                revert InvalidEthereumAddressOwner(owners[i]);
-            }
-
             _addOwnerAtIndex(owners[i], nextOwnerIndex_++);
         }
         $.nextOwnerIndex = nextOwnerIndex_;
     }
 
     function _addOwnerAtIndex(bytes memory owner, uint256 index) internal virtual {
+        _validateOwner(owner);
         if (isOwnerBytes(owner)) revert AlreadyOwner(owner);
 
         MultiOwnableStorage storage $ = _getMultiOwnableStorage();
         $.isOwner[owner] = true;
         $.ownerAtIndex[index] = owner;
 
         emit AddOwner(index, owner);
     }
 
+    function _validateOwner(bytes memory owner) internal view virtual {
+        if (owner.length != 32 && owner.length != 64) {
+            revert InvalidOwnerBytesLength(owner);
+        }
+
+        if (owner.length == 32) {
+            bytes32 ownerWord = bytes32(owner);
+            if (uint256(ownerWord) > type(uint160).max) {
+                revert InvalidEthereumAddressOwner(owner);
+            }
+
+            address ownerAddress = address(uint160(uint256(ownerWord)));
+            if (ownerAddress == address(0) || ownerAddress == address(this)) {
+                revert InvalidEthereumAddressOwner(owner);
+            }
+
+            return;
+        }
+
+        (uint256 x, uint256 y) = abi.decode(owner, (uint256, uint256));
+        if (!FCL_Elliptic_ZZ.ecAff_isOnCurve(x, y)) {
+            revert InvalidPublicKeyOwner(owner);
+        }
+    }
+
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
 
     function _getMultiOwnableStorage() internal pure returns (MultiOwnableStorage storage $) {
         assembly ("memory-safe") {
             $.slot := MUTLI_OWNABLE_STORAGE_LOCATION
         }
     }
 }
```

### Affected files
- `contracts/src/wallets/HPSmartWallet.sol`
- `contracts/src/wallets/base/MultiOwnable.sol`

### Validation output

```
[output truncated: 33 lines & 1.564453125 KB skipped]

Failing tests:
Encountered 1 failing test in test/wallets/WalletHarnessPlaceholder.t.sol:WalletHarnessPlaceholderTest
[FAIL: InvalidEthereumAddressOwner(0x0000000000000000000000000000000000000000000000000000000000000000)] test_poc_zeroAddressOwnerCanBrickWalletAndFreezeAssets() (gas: 281196)

Encountered a total of 1 failing tests, 0 tests succeeded

Tip: Run `forge test --rerun` to retry only the 1 failed test

Warning: Found unknown `depth` config key in section `fuzz` defined in foundry.toml.
```

---

# Invalid Owners Trap Funds
**#85729**
- Severity: High
- Validity: Unreviewed

## Source locations

### `contracts/src/wallets/HPSmartWalletFactory.sol` (2 locations)
#### Lines 42-67 — _`createAccount` only rejects an empty owner array, then initializes and flags the proxy; `getAddress` predicts an address for any owners/nonce pair._

```
    function createAccount(bytes[] calldata owners, uint256 nonce)
        external
        payable
        virtual
        returns (HPSmartWallet account)
    {
        if (owners.length == 0) {
            revert OwnerRequired();
        }

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
    function getAddress(bytes[] calldata owners, uint256 nonce) external view returns (address) {
        return LibClone.predictDeterministicAddress(initCodeHash(), _getSalt(owners, nonce), address(this));
```

⋯
#### Lines 109-110 — _The salt is derived directly from unvalidated owner bytes and nonce._

```
    function _getSalt(bytes[] calldata owners, uint256 nonce) internal pure returns (bytes32) {
        return keccak256(abi.encode(owners, nonce));
```

### `contracts/src/wallets/base/MultiOwnable.sol` (2 locations)
#### Lines 84-103 — _Wallet initialization validates lengths/range and duplicates after prediction, but does not reject `address(0)`._

```
    function _initializeOwners(bytes[] memory owners) internal virtual {
        MultiOwnableStorage storage $ = _getMultiOwnableStorage();
        uint256 nextOwnerIndex_ = $.nextOwnerIndex;
        for (uint256 i; i < owners.length; i++) {
            if (owners[i].length != 32 && owners[i].length != 64) {
                revert InvalidOwnerBytesLength(owners[i]);
            }

            if (owners[i].length == 32 && uint256(bytes32(owners[i])) > type(uint160).max) {
                revert InvalidEthereumAddressOwner(owners[i]);
            }

            _addOwnerAtIndex(owners[i], nextOwnerIndex_++);
        }
        $.nextOwnerIndex = nextOwnerIndex_;
    }

    function _addOwnerAtIndex(bytes memory owner, uint256 index) internal virtual {
        if (isOwnerBytes(owner)) revert AlreadyOwner(owner);

```

⋯
#### Lines 126-132 — _Owner-gated direct calls require `msg.sender` to match an owner address or the wallet itself._

```
    function _checkOwner() internal view virtual {
        if (isOwnerAddress(msg.sender) || (msg.sender == address(this))) {
            return;
        }

        revert Unauthorized();
    }
```

### `contracts/lib/solady/src/utils/SignatureCheckerLib.sol`
#### Lines 32-38 — _ECDSA/ERC-1271 signature validation returns false immediately for `address(0)` signers._

```
    function isValidSignatureNow(address signer, bytes32 hash, bytes memory signature)
        internal
        view
        returns (bool isValid)
    {
        if (signer == address(0)) return isValid;
        /// @solidity memory-safe-assembly
```

### `contracts/src/wallets/HPDepositRouter.sol` (2 locations)
#### Lines 87-103 — _Native deposits explicitly support counterfactual wallet addresses and forward ETH to the supplied wallet._

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

⋯
#### Lines 106-152 — _Token deposits forward net tokens and converted gas skim to the supplied wallet address._

```
    /// @notice ERC-20 deposit: the skim is converted to native ETH (unwrap / redeem / swap depending on the
    ///         token) and funds gas credit; the remaining principal is forwarded to `wallet` in-kind.
    /// @param minEthOut Lower bound on the ETH received for the skim (slippage protection on the swap path;
    ///        pass the UI quote minus tolerance). May be 0 for the deterministic WETH/SETH paths.
    function depositToken(address token, uint256 amount, address wallet, uint256 minEthOut) external {
        if (wallet == address(0)) revert ZeroWallet();
        if (amount == 0) revert ZeroAmount();

        TokenClass class = _classify(token);

        token.safeTransferFrom(msg.sender, address(this), amount);

        uint256 skim = (amount * skimBps) / BPS_DENOMINATOR;

        // SETH redeems in whole multiples of its exchange rate; a sub-rate skim cannot convert, so waive it.
        if (class == TokenClass.Redeem && skim < SETH(payable(token)).EXCHANGE_RATE()) {
            skim = 0;
        }

        uint256 net = amount - skim;
        uint256 ethOut;

        if (skim != 0) {
            uint256 balanceBefore = address(this).balance;

            if (class == TokenClass.Unwrap) {
                IWETH9(token).withdraw(skim);
            } else if (class == TokenClass.Redeem) {
                SETH(payable(token)).withdraw(skim);
            } else {
                address converter = _getAddress(_addressKey("DEPOSIT_CONVERTER"));
                token.safeApprove(converter, skim);
                IDepositConverter(converter).convertToEth(token, skim, minEthOut);
                token.safeApprove(converter, 0);
            }

            ethOut = address(this).balance - balanceBefore;
            if (ethOut < minEthOut) revert InsufficientEthOut(ethOut, minEthOut);

            if (ethOut != 0) {
                _paymaster().depositFor{ value: ethOut }(wallet);
            }
        }

        token.safeTransfer(wallet, net);

        emit DepositProcessed(wallet, token, amount, ethOut, net);
```

### `contracts/src/wallets/HPPaymaster.sol`
#### Lines 98-108 — _Gas credit can be funded for a counterfactual wallet address before deployment._

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

## Description

`getAddress` returns a CREATE2 prediction for any `owners` byte array, while `createAccount` only rejects an empty array before deploying and delegating the real owner checks to wallet initialization. The initializer rejects malformed owner encodings, duplicate owners, and 32-byte values outside the address range, so the factory can advertise counterfactual addresses that can never be deployed. The same validation gap also permits `abi.encode(address(0))` as an owner: it satisfies the initializer’s length/range checks, but no transaction can originate from the zero address and Solady’s signature checker always rejects a zero signer. Because the router and paymaster explicitly support pre-deployment funding of arbitrary wallet addresses, assets and gas credit can be sent to these predicted or created-but-unusable wallets. The resulting address is either undeployable by the factory or permanently lacks an authorized execution path, so the funded value cannot be recovered.

## Root cause

The factory exposes `getAddress` as a counterfactual wallet oracle without sharing the deployability checks used by `createAccount` and without rejecting semantically unusable owners such as `address(0)`. Owner validation is split between the factory and `MultiOwnable.initialize`, leaving prediction, deployment, and authorization with inconsistent validity rules.

## Impact

Funds routed to a counterfactual address derived from malformed owner data are permanently stuck because `createAccount` can never finish deployment for that salt. Funds routed to a zero-owner wallet are likewise stuck because the wallet is marked legitimate but cannot validate signatures or owner-gated calls.

## Proof of concept

### Test case

```
// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { UserOperation06 } from "@account-abstraction/legacy/v06/UserOperation06.sol";

import { HPDepositRouter } from "@src/wallets/HPDepositRouter.sol";
import { HPPaymaster } from "@src/wallets/HPPaymaster.sol";
import { HPSmartWallet } from "@src/wallets/HPSmartWallet.sol";
import { MultiOwnable } from "@src/wallets/base/MultiOwnable.sol";

import { WalletTestBase } from "./WalletTestBase.sol";

contract PoCMockEntryPoint {
    mapping(address account => uint256 amount) public balanceOf;

    function depositTo(address account) external payable {
        balanceOf[account] += msg.value;
    }
}

contract WalletHarnessPlaceholderTest is WalletTestBase {
    uint256 internal constant SKIM_BPS = 50; // 0.5%

    PoCMockEntryPoint internal mockEntryPoint;
    HPPaymaster internal paymaster;
    HPDepositRouter internal router;

    address internal user = makeAddr("user");
    address internal recipient = makeAddr("recipient");

    function setUp() public override {
        super.setUp();

        mockEntryPoint = new PoCMockEntryPoint();
        paymaster = new HPPaymaster(address(provider), address(mockEntryPoint));
        router = new HPDepositRouter(address(provider), SKIM_BPS);

        vm.prank(admin);
        provider.registerName("PAYMASTER", address(paymaster));

        vm.deal(user, 10 ether);
    }

    function test_poc_invalidOwnerPrediction_canReceiveFundsButCanNeverBeDeployed() public {
        bytes[] memory malformedOwners = new bytes[](1);
        malformedOwners[0] = hex"010203"; // 3-byte owner blob passes getAddress/createAccount length gate but fails initialize().

        address predicted = factory.getAddress(malformedOwners, 7);

        vm.prank(user);
        router.depositNative{ value: 1 ether }(predicted);

        assertEq(predicted.balance, 0.995 ether, "router forwarded ETH to undeployed counterfactual");
        assertEq(paymaster.gasCredit(predicted), 0.005 ether, "router also credited gas to same unusable address");
        assertEq(mockEntryPoint.balanceOf(address(paymaster)), 0.005 ether, "skim was deposited into paymaster backing");
        assertEq(predicted.code.length, 0, "counterfactual is still undeployed before createAccount");

        vm.expectRevert(abi.encodeWithSelector(MultiOwnable.InvalidOwnerBytesLength.selector, malformedOwners[0]));
        factory.createAccount(malformedOwners, 7);

        assertEq(predicted.code.length, 0, "factory rollback leaves no contract deployed at funded address");
        assertEq(predicted.balance, 0.995 ether, "funded ETH remains stranded at undeployable address");
        assertEq(paymaster.gasCredit(predicted), 0.005 ether, "gas credit remains assigned to undeployable address");
        assertFalse(factory.isHPWallet(predicted), "failed deployment never becomes a legitimate wallet");
    }

    function test_poc_zeroOwnerWallet_acceptsDepositsButCannotAuthorizeRecovery() public {
        bytes[] memory zeroOwner = _singleOwner(address(0));
        HPSmartWallet wallet = factory.createAccount(zeroOwner, 11);

        assertTrue(factory.isHPWallet(address(wallet)), "factory marks the zero-owner wallet as legitimate");
        assertTrue(wallet.isOwnerAddress(address(0)), "zero address is stored as the sole owner");
        assertEq(wallet.ownerCount(), 1, "wallet has exactly one unusable owner");

        vm.prank(user);
        router.depositNative{ value: 1 ether }(address(wallet));

        assertEq(address(wallet).balance, 0.995 ether, "wallet accepted user principal");
        assertEq(paymaster.gasCredit(address(wallet)), 0.005 ether, "wallet also received sponsored gas credit");

        vm.prank(user);
        vm.expectRevert(MultiOwnable.Unauthorized.selector);
        wallet.execute(recipient, 0.1 ether, "");
        assertEq(recipient.balance, 0, "unauthorized caller cannot recover funds");

        bytes32 digest = keccak256("stuck funds");
        bytes memory impossibleSig = abi.encode(HPSmartWallet.SignatureWrapper(0, hex"00"));
        assertEq(wallet.isValidSignature(digest, impossibleSig), bytes4(0xffffffff), "ERC-1271 rejects the zero owner");

        UserOperation06 memory op = _baseUserOp(address(wallet), 0);
        op.signature = impossibleSig;

        vm.prank(entryPointAddr);
        uint256 validationData = wallet.validateUserOp(op, keccak256("user op"), 0);
        assertEq(validationData, 1, "ERC-4337 validation cannot authorize execution for the zero owner");

        assertEq(address(wallet).balance, 0.995 ether, "funds remain in the unusable wallet");
        assertEq(paymaster.gasCredit(address(wallet)), 0.005 ether, "gas credit also remains trapped");
    }
}
```

### Setup script

```
#!/bin/bash
set -e

# install dependencies
cd contracts && rm -rf out cache && forge build
```

### Output

```
[output truncated: 25 lines & 1.041015625 KB skipped]
   |     ^ (Relevant source part starts here and spans across multiple lines).


Ran 2 tests for test/wallets/WalletHarnessPlaceholder.t.sol:WalletHarnessPlaceholderTest
[PASS] test_poc_invalidOwnerPrediction_canReceiveFundsButCanNeverBeDeployed() (gas: 248502)
[PASS] test_poc_zeroOwnerWallet_acceptsDepositsButCannotAuthorizeRecovery() (gas: 412053)
Suite result: ok. 2 passed; 0 failed; 0 skipped; finished in 2.69ms (710.05µs CPU time)

Ran 1 test suite in 10.22ms (2.69ms CPU time): 2 tests passed, 0 failed, 0 skipped (2 total tests)
Warning: Found unknown `depth` config key in section `fuzz` defined in foundry.toml.
```

### Considerations

Verified with `cd contracts && forge test --match-path test/wallets/WalletHarnessPlaceholder.t.sol -vvv`. The PoC demonstrates the two public-entry exploit paths in the finding using native-ETH funding only: `HPDepositRouter.depositNative` funds an undeployable counterfactual returned by `getAddress`, and a wallet created with `abi.encode(address(0))` receives deposits but cannot authorize `execute`, ERC-1271 validation, or ERC-4337 validation. The same trap applies to token deposits and direct `HPPaymaster.depositFor`, but those redundant funding surfaces were not needed for executable proof.

## Remediation

### Explanation

Validated owner payloads in HPSmartWalletFactory before both createAccount and getAddress, mirroring wallet deployability checks and rejecting zero-address owners so counterfactual prediction and deployment stay consistent and unusable zero-owner wallets cannot be created.

### Patch

```diff
diff --git a/contracts/src/wallets/HPSmartWalletFactory.sol b/contracts/src/wallets/HPSmartWalletFactory.sol
--- a/contracts/src/wallets/HPSmartWalletFactory.sol
+++ b/contracts/src/wallets/HPSmartWalletFactory.sol
@@ -1,112 +1,139 @@
 // SPDX-License-Identifier: AGPL-3.0
 pragma solidity ^0.8.34;
 
 import { LibClone } from "@solady/utils/LibClone.sol";
 
 import { AddressBook } from "@core/AddressBook.sol";
 
+import { MultiOwnable } from "./base/MultiOwnable.sol";
 import { HPSmartWallet } from "./HPSmartWallet.sol";
 import { IHPWalletFactory } from "./interfaces/IHPWalletFactory.sol";
 
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
-        if (owners.length == 0) {
-            revert OwnerRequired();
-        }
+        _validateOwners(owners);
 
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
     function getAddress(bytes[] calldata owners, uint256 nonce) external view returns (address) {
+        _validateOwners(owners);
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
 
+    function _validateOwners(bytes[] calldata owners) internal pure {
+        if (owners.length == 0) {
+            revert OwnerRequired();
+        }
+
+        for (uint256 i; i < owners.length; ++i) {
+            bytes calldata owner = owners[i];
+            if (owner.length != 32 && owner.length != 64) {
+                revert MultiOwnable.InvalidOwnerBytesLength(owner);
+            }
+
+            if (owner.length == 32) {
+                uint256 ownerValue = uint256(abi.decode(owner, (bytes32)));
+                if (ownerValue == 0 || ownerValue > type(uint160).max) {
+                    revert MultiOwnable.InvalidEthereumAddressOwner(owner);
+                }
+            }
+
+            bytes32 ownerHash = keccak256(owner);
+            for (uint256 j; j < i; ++j) {
+                if (ownerHash == keccak256(owners[j])) {
+                    revert MultiOwnable.AlreadyOwner(owner);
+                }
+            }
+        }
+    }
+
     function _getSalt(bytes[] calldata owners, uint256 nonce) internal pure returns (bytes32) {
         return keccak256(abi.encode(owners, nonce));
     }
 }
```

### Affected files
- `contracts/src/wallets/HPSmartWalletFactory.sol`

### Validation output

```
[output truncated: 35 lines & 1.6982421875 KB skipped]
Failing tests:
Encountered 2 failing tests in test/wallets/WalletHarnessPlaceholder.t.sol:WalletHarnessPlaceholderTest
[FAIL: InvalidOwnerBytesLength(0x010203)] test_poc_invalidOwnerPrediction_canReceiveFundsButCanNeverBeDeployed() (gas: 6933)
[FAIL: InvalidEthereumAddressOwner(0x0000000000000000000000000000000000000000000000000000000000000000)] test_poc_zeroOwnerWallet_acceptsDepositsButCannotAuthorizeRecovery() (gas: 7181)

Encountered a total of 2 failing tests, 0 tests succeeded

Tip: Run `forge test --rerun` to retry only the 2 failed tests

Warning: Found unknown `depth` config key in section `fuzz` defined in foundry.toml.
```

---

# Unbounded priority fee aborts gas settlement
**#85730**
- Severity: Low
- Validity: Invalid

## Source locations

### `contracts/src/wallets/HPPaymaster.sol` (3 locations)
#### Lines 122-143 — _validation bounds only maxFeePerGas (line 133); maxPriorityFeePerGas is passed through to context (line 142) unvalidated_

```
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
    }
```

⋯
#### Lines 145-149 — _natspec asserts postOp 'Never reverts (a revert would force a postOpReverted re-call)' — the invariant this finding violates_

```
    /// @inheritdoc IPaymaster06
    /// @dev Never reverts (a revert would force a `postOpReverted` re-call). Charges `actualGasCost` plus the
    ///      postOp margin priced at the *user-operation* fee rate the EntryPoint settles at —
    ///      `min(maxFeePerGas, maxPriorityFeePerGas + basefee)`, not `tx.gasprice` — and refunds the reservation
    ///      remainder to the wallet.
```

⋯
#### Lines 150-160 — _postOp computes feePerGas = maxPriorityFeePerGas + block.basefee (line 154) in checked arithmetic; reverts on overflow before the clamp on line 155_

```
    function postOp(PostOpMode, bytes calldata context, uint256 actualGasCost) external onlyEntryPoint {
        (address wallet, uint256 reserved, uint256 maxFeePerGas, uint256 maxPriorityFeePerGas) =
            abi.decode(context, (address, uint256, uint256, uint256));

        uint256 feePerGas = maxPriorityFeePerGas + block.basefee;
        if (maxFeePerGas < feePerGas) feePerGas = maxFeePerGas;

        uint256 charge = actualGasCost + POST_OP_GAS * feePerGas;
        if (charge > reserved) charge = reserved;

        uint256 refund = reserved - charge;
```

## Description

The gas-settlement path decodes the user-operation `maxPriorityFeePerGas` from `context` and computes `feePerGas = maxPriorityFeePerGas + block.basefee` in default checked arithmetic before clamping it down to `maxFeePerGas`. The validation phase only ever bounds `userOp.maxFeePerGas` (it sizes the credit reservation as `maxCost + POST_OP_GAS * userOp.maxFeePerGas`) and never inspects `maxPriorityFeePerGas`, so an attacker who controls a registered, minimally-funded HP wallet can submit an operation with a tiny `maxFeePerGas` (which passes the reservation check) and `maxPriorityFeePerGas = type(uint256).max`. On any chain where `block.basefee >= 1` (Base mainnet), the addition overflows and the settlement call reverts, even though the contract's own natspec promises it `Never reverts`. Because `simulateValidation` does not execute the settlement hook, the malformed operation is admissible into the mempool yet aborts execution. The v0.6 EntryPoint reacts to a reverting settlement hook by re-invoking it in the `postOpReverted` mode; the deterministic overflow reverts again and surfaces as `FailedOp`, reverting the entire `handleOps` bundle.

## Root cause

`postOp` performs checked arithmetic on the attacker-controlled `userOp.maxPriorityFeePerGas` (`maxPriorityFeePerGas + block.basefee`) even though `validatePaymasterUserOp` only ever bounds `maxFeePerGas`, so an overflow reverts the settlement hook that is documented to never revert.

## Impact

A registered wallet can craft operations that pass validation simulation but deterministically revert the whole bundle during settlement, so any honest bundler that batches the operation loses the gas it spent and any co-bundled honest operations are dropped. The attacker pays nothing because the reverted transaction rolls back the credit reservation, making the griefing free and repeatable against the sponsorship pipeline.
