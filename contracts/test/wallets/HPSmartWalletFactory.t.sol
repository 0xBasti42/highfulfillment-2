// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { HPSmartWallet } from "@src/wallets/HPSmartWallet.sol";
import { HPSmartWalletFactory } from "@src/wallets/HPSmartWalletFactory.sol";
import { DefaultCrypto, DefaultStablecoin } from "@src/wallets/types/HPWalletTypes.sol";

import { WalletTestBase } from "./WalletTestBase.sol";

contract HPSmartWalletFactoryTest is WalletTestBase {
    event AccountCreated(address indexed account, bytes[] owners, uint256 nonce);

    function test_createAccount_matchesCounterfactualAddress() public {
        bytes[] memory owners = _singleOwner(ownerEOA);
        address predicted = factory.getAddress(owners, 0);

        HPSmartWallet wallet = factory.createAccount(owners, 0);

        assertEq(address(wallet), predicted);
        assertEq(wallet.implementation(), address(walletImplementation));
    }

    function test_createAccount_initializesOwnersAndSettings() public {
        HPSmartWallet wallet = _createWallet(ownerEOA, 0);

        assertTrue(wallet.isOwnerAddress(ownerEOA));
        assertEq(wallet.ownerCount(), 1);
        assertEq(uint8(wallet.defaultCrypto()), uint8(DefaultCrypto.ETH));
        assertEq(uint8(wallet.defaultStablecoin()), uint8(DefaultStablecoin.TGBP));
    }

    function test_createAccount_flagsAndEnumeratesWallet() public {
        HPSmartWallet wallet = _createWallet(ownerEOA, 0);

        assertTrue(factory.isHPWallet(address(wallet)));
        assertEq(factory.walletCount(), 1);
        assertEq(factory.walletAt(0), address(wallet));
        assertEq(factory.getAllWallets()[0], address(wallet));
    }

    function test_isHPWallet_falseForArbitraryAddress() public {
        assertFalse(factory.isHPWallet(makeAddr("notAWallet")));
    }

    function test_createAccount_emitsAccountCreated() public {
        bytes[] memory owners = _singleOwner(ownerEOA);
        address predicted = factory.getAddress(owners, 0);

        vm.expectEmit(true, false, false, true, address(factory));
        emit AccountCreated(predicted, owners, 0);

        factory.createAccount(owners, 0);
    }

    function test_createAccount_isIdempotent() public {
        bytes[] memory owners = _singleOwner(ownerEOA);

        HPSmartWallet first = factory.createAccount(owners, 0);
        HPSmartWallet second = factory.createAccount(owners, 0);

        assertEq(address(first), address(second));
        assertEq(factory.walletCount(), 1);
    }

    function test_createAccount_differentNonceDifferentAddress() public {
        bytes[] memory owners = _singleOwner(ownerEOA);

        address a = factory.getAddress(owners, 0);
        address b = factory.getAddress(owners, 1);

        assertTrue(a != b);
    }

    function test_createAccount_revertsWithoutOwners() public {
        bytes[] memory owners = new bytes[](0);

        vm.expectRevert(HPSmartWalletFactory.OwnerRequired.selector);
        factory.createAccount(owners, 0);
    }

    function test_initialize_revertsWhenAlreadyInitialized() public {
        HPSmartWallet wallet = _createWallet(ownerEOA, 0);

        vm.expectRevert(HPSmartWallet.Initialized.selector);
        wallet.initialize(_singleOwner(makeAddr("attacker")));
    }

    function test_constructor_revertsForUndeployedImplementation() public {
        vm.expectRevert(HPSmartWalletFactory.ImplementationUndeployed.selector);
        new HPSmartWalletFactory(makeAddr("notAContract"), address(provider));
    }
}
