// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { HPSmartWallet } from "@src/wallets/HPSmartWallet.sol";
import { MultiOwnable } from "@src/wallets/base/MultiOwnable.sol";

import { WalletTestBase } from "./WalletTestBase.sol";

/// @notice Regression coverage for the Zellic v12 audit findings on the wallet suite.
contract WalletSecurityFixesTest is WalletTestBase {
    function _twoOwners(address a, address b) internal pure returns (bytes[] memory owners) {
        owners = new bytes[](2);
        owners[0] = abi.encode(a);
        owners[1] = abi.encode(b);
    }

    // --------------------------------------------
    //  #84991 / #84981: no owner -> wallet registry to poison or squat
    // --------------------------------------------

    /// @dev Two wallets sharing an owner key both deploy: there is no global owner exclusivity to collide on,
    ///      so a counterfactual address can never be bricked by another wallet claiming a shared key.
    function test_overlappingOwnerKeysDoNotBlockDeployment() public {
        address shared = makeAddr("shared");
        address attacker = makeAddr("attacker");

        HPSmartWallet a = factory.createAccount(_twoOwners(shared, attacker), 0);
        HPSmartWallet b = _createWallet(shared, 1);

        assertTrue(factory.isHPWallet(address(a)));
        assertTrue(factory.isHPWallet(address(b)));
        assertTrue(a.isOwnerAddress(shared));
        assertTrue(b.isOwnerAddress(shared));
    }

    /// @dev A wallet adding an owner that another wallet already uses no longer reverts (the cross-wallet
    ///      registry coupling that previously enabled key squatting is gone).
    function test_addOwnerNotBlockedByOtherWallet() public {
        address ownerA = makeAddr("ownerA");
        address ownerB = makeAddr("ownerB");
        address shared = makeAddr("shared");

        HPSmartWallet a = _createWallet(ownerA, 0);
        HPSmartWallet b = _createWallet(ownerB, 1);

        vm.prank(ownerA);
        a.addOwnerAddress(shared);

        vm.prank(ownerB);
        b.addOwnerAddress(shared);

        assertTrue(a.isOwnerAddress(shared));
        assertTrue(b.isOwnerAddress(shared));
    }

    // --------------------------------------------
    //  #84982: the final owner can never be removed
    // --------------------------------------------

    function test_cannotRemoveLastOwner() public {
        HPSmartWallet wallet = _createWallet(ownerEOA, 0);

        vm.prank(ownerEOA);
        vm.expectRevert(MultiOwnable.LastOwner.selector);
        wallet.removeOwnerAtIndex(0, abi.encode(ownerEOA));

        // Wallet remains controllable.
        assertEq(wallet.ownerCount(), 1);
        assertTrue(wallet.isOwnerAddress(ownerEOA));
    }

    function test_canRemoveDownToOneOwner() public {
        HPSmartWallet wallet = _createWallet(ownerEOA, 0);
        address second = makeAddr("second");

        vm.startPrank(ownerEOA);
        wallet.addOwnerAddress(second);
        wallet.removeOwnerAtIndex(1, abi.encode(second));
        vm.stopPrank();

        assertEq(wallet.ownerCount(), 1);
        assertTrue(wallet.isOwnerAddress(ownerEOA));
        assertFalse(wallet.isOwnerAddress(second));
    }

    // --------------------------------------------
    //  #84990: ERC-1271 reports failure, never reverts
    // --------------------------------------------

    function test_isValidSignature_returnsFailureForMalformedBlob() public {
        HPSmartWallet wallet = _createWallet(ownerEOA, 0);
        bytes32 hash = keccak256("message");

        (bool success, bytes memory ret) =
            address(wallet).staticcall(abi.encodeCall(wallet.isValidSignature, (hash, bytes(""))));

        assertTrue(success, "must not revert");
        assertEq(abi.decode(ret, (bytes4)), bytes4(0xffffffff));
    }

    function test_isValidSignature_returnsFailureForRemovedOwnerIndex() public {
        HPSmartWallet wallet = _createWallet(ownerEOA, 0);
        address second = makeAddr("second");

        vm.startPrank(ownerEOA);
        wallet.addOwnerAddress(second);
        wallet.removeOwnerAtIndex(1, abi.encode(second));
        vm.stopPrank();

        bytes32 hash = keccak256("message");
        bytes memory staleSig =
            abi.encode(HPSmartWallet.SignatureWrapper({ ownerIndex: 1, signatureData: hex"deadbeef" }));

        (bool success, bytes memory ret) =
            address(wallet).staticcall(abi.encodeCall(wallet.isValidSignature, (hash, staleSig)));

        assertTrue(success, "must not revert");
        assertEq(abi.decode(ret, (bytes4)), bytes4(0xffffffff));
    }

    function test_isValidSignature_stillAcceptsValidSignature() public {
        HPSmartWallet wallet = _createWallet(ownerEOA, 0);
        bytes32 hash = keccak256("message");
        bytes memory sig = _eoaSignature(ownerPk, wallet.replaySafeHash(hash), 0);

        assertEq(wallet.isValidSignature(hash, sig), bytes4(0x1626ba7e));
    }

    function test_isValidSignatureExternal_selfOnly() public {
        HPSmartWallet wallet = _createWallet(ownerEOA, 0);
        vm.expectRevert(MultiOwnable.Unauthorized.selector);
        wallet.isValidSignatureExternal(keccak256("x"), "");
    }
}
