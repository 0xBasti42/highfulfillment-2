// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { HPSmartWallet } from "@src/wallets/HPSmartWallet.sol";
import { DefaultCrypto, DefaultStablecoin } from "@src/wallets/types/HPWalletTypes.sol";
import { MultiOwnable } from "@src/wallets/base/MultiOwnable.sol";

import { WalletTestBase } from "./WalletTestBase.sol";

contract HPSmartWalletV2 is HPSmartWallet {
    constructor(address addressProvider_) HPSmartWallet(addressProvider_) { }

    function walletVersion() external pure returns (uint256) {
        return 2;
    }
}

contract HPSmartWalletUpgradeTest is WalletTestBase {
    HPSmartWallet internal wallet;
    HPSmartWalletV2 internal implementationV2;

    function setUp() public override {
        super.setUp();
        wallet = _createWallet(ownerEOA, 0);
        implementationV2 = new HPSmartWalletV2(address(provider));
    }

    function test_upgrade_preservesOwnersSettingsAndAccountSet() public {
        address secondOwner = makeAddr("secondOwner");
        address pm = makeAddr("positionManager");
        address vault = makeAddr("vaultManager");

        vm.startPrank(ownerEOA);
        wallet.addOwnerAddress(secondOwner);
        wallet.setDefaultCrypto(DefaultCrypto.BTC);
        wallet.setDefaultStablecoin(DefaultStablecoin.EURC);
        wallet.setAccountSet(pm, vault);

        wallet.upgradeToAndCall(address(implementationV2), "");
        vm.stopPrank();

        assertEq(wallet.implementation(), address(implementationV2));
        assertEq(HPSmartWalletV2(payable(address(wallet))).walletVersion(), 2);

        // MultiOwnable storage preserved.
        assertTrue(wallet.isOwnerAddress(ownerEOA));
        assertTrue(wallet.isOwnerAddress(secondOwner));
        assertEq(wallet.ownerCount(), 2);

        // WalletSettings storage preserved.
        assertEq(uint8(wallet.defaultCrypto()), uint8(DefaultCrypto.BTC));
        assertEq(uint8(wallet.defaultStablecoin()), uint8(DefaultStablecoin.EURC));
        assertEq(wallet.defaultCryptoAddress(), cbBTC);
        assertEq(wallet.defaultStablecoinAddress(), eurc);

        // AccountSet storage preserved.
        (address pmAfter, address vaultAfter) = wallet.accountSet();
        assertEq(pmAfter, pm);
        assertEq(vaultAfter, vault);
    }

    function test_upgrade_factoryFlagUnaffected() public {
        vm.prank(ownerEOA);
        wallet.upgradeToAndCall(address(implementationV2), "");

        // The factory's wallet-keyed legitimacy flag is independent of the wallet implementation.
        assertTrue(factory.isHPWallet(address(wallet)));
    }

    function test_upgrade_revertsForNonOwner() public {
        vm.prank(makeAddr("stranger"));
        vm.expectRevert(MultiOwnable.Unauthorized.selector);
        wallet.upgradeToAndCall(address(implementationV2), "");
    }
}
