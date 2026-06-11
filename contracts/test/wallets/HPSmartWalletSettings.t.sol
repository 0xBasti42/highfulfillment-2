// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { AddressNotFound } from "@core/AddressBook.sol";
import { HPSmartWallet } from "@src/wallets/HPSmartWallet.sol";
import { DefaultCrypto, DefaultStablecoin } from "@src/wallets/types/HPWalletTypes.sol";
import { MultiOwnable } from "@src/wallets/base/MultiOwnable.sol";

import { WalletTestBase } from "./WalletTestBase.sol";

contract HPSmartWalletSettingsTest is WalletTestBase {
    HPSmartWallet internal wallet;

    event DefaultCryptoUpdated(DefaultCrypto indexed previous, DefaultCrypto indexed current);
    event DefaultStablecoinUpdated(DefaultStablecoin indexed previous, DefaultStablecoin indexed current);
    event AccountSetUpdated(address indexed positionManager, address indexed vaultManager);

    function setUp() public override {
        super.setUp();
        wallet = _createWallet(ownerEOA, 0);
    }

    // --------------------------------------------
    //  Defaults
    // --------------------------------------------

    function test_defaultsSeededOnInitialize() public view {
        assertEq(uint8(wallet.defaultCrypto()), uint8(DefaultCrypto.ETH));
        assertEq(uint8(wallet.defaultStablecoin()), uint8(DefaultStablecoin.TGBP));

        (DefaultCrypto crypto, DefaultStablecoin stablecoin) = wallet.walletSettings();
        assertEq(uint8(crypto), uint8(DefaultCrypto.ETH));
        assertEq(uint8(stablecoin), uint8(DefaultStablecoin.TGBP));
    }

    /// @dev Audit #84983: init reports the real previous value (enum zero = BTC), not ETH.
    function test_initialize_emitsCorrectPreviousCryptoValue() public {
        vm.expectEmit(true, true, false, false);
        emit DefaultCryptoUpdated(DefaultCrypto.BTC, DefaultCrypto.ETH);
        // A fresh wallet at a new nonce re-runs initialize during creation.
        _createWallet(makeAddr("freshOwner"), 1);
    }

    // --------------------------------------------
    //  Account set (PositionManager / VaultManager)
    // --------------------------------------------

    function test_accountSet_defaultsToZero() public view {
        (address pm, address vault) = wallet.accountSet();
        assertEq(pm, address(0));
        assertEq(vault, address(0));
    }

    function test_setAccountSet_byOwner() public {
        address pm = makeAddr("positionManager");
        address vault = makeAddr("vaultManager");

        vm.expectEmit(true, true, false, false, address(wallet));
        emit AccountSetUpdated(pm, vault);

        vm.prank(ownerEOA);
        wallet.setAccountSet(pm, vault);

        (address pmOut, address vaultOut) = wallet.accountSet();
        assertEq(pmOut, pm);
        assertEq(vaultOut, vault);
    }

    function test_setAccountSet_viaEntryPointExecuteSelfCall() public {
        address pm = makeAddr("positionManager");
        address vault = makeAddr("vaultManager");

        vm.prank(entryPointAddr);
        wallet.execute(address(wallet), 0, abi.encodeCall(HPSmartWallet.setAccountSet, (pm, vault)));

        (address pmOut, address vaultOut) = wallet.accountSet();
        assertEq(pmOut, pm);
        assertEq(vaultOut, vault);
    }

    function test_setAccountSet_revertsForNonOwner() public {
        vm.prank(makeAddr("stranger"));
        vm.expectRevert(MultiOwnable.Unauthorized.selector);
        wallet.setAccountSet(makeAddr("pm"), makeAddr("vault"));
    }

    // --------------------------------------------
    //  Setters
    // --------------------------------------------

    function test_setDefaultCrypto_byOwner() public {
        vm.expectEmit(true, true, false, false, address(wallet));
        emit DefaultCryptoUpdated(DefaultCrypto.ETH, DefaultCrypto.BTC);

        vm.prank(ownerEOA);
        wallet.setDefaultCrypto(DefaultCrypto.BTC);

        assertEq(uint8(wallet.defaultCrypto()), uint8(DefaultCrypto.BTC));
    }

    function test_setDefaultStablecoin_byOwner() public {
        vm.expectEmit(true, true, false, false, address(wallet));
        emit DefaultStablecoinUpdated(DefaultStablecoin.TGBP, DefaultStablecoin.USDC);

        vm.prank(ownerEOA);
        wallet.setDefaultStablecoin(DefaultStablecoin.USDC);

        assertEq(uint8(wallet.defaultStablecoin()), uint8(DefaultStablecoin.USDC));
    }

    /// @dev The ERC-4337 path: EntryPoint -> execute -> self-call, authorized via `msg.sender == address(this)`.
    function test_setDefaultCrypto_viaEntryPointExecute() public {
        vm.prank(entryPointAddr);
        wallet.execute(address(wallet), 0, abi.encodeCall(HPSmartWallet.setDefaultCrypto, (DefaultCrypto.SETH)));

        assertEq(uint8(wallet.defaultCrypto()), uint8(DefaultCrypto.SETH));
    }

    function test_setDefaultStablecoin_viaOwnerExecuteSelfCall() public {
        vm.prank(ownerEOA);
        wallet.execute(
            address(wallet), 0, abi.encodeCall(HPSmartWallet.setDefaultStablecoin, (DefaultStablecoin.DAI))
        );

        assertEq(uint8(wallet.defaultStablecoin()), uint8(DefaultStablecoin.DAI));
    }

    function test_setters_revertForNonOwner() public {
        address stranger = makeAddr("stranger");

        vm.prank(stranger);
        vm.expectRevert(MultiOwnable.Unauthorized.selector);
        wallet.setDefaultCrypto(DefaultCrypto.BTC);

        vm.prank(stranger);
        vm.expectRevert(MultiOwnable.Unauthorized.selector);
        wallet.setDefaultStablecoin(DefaultStablecoin.USDC);
    }

    // --------------------------------------------
    //  AddressProvider resolution
    // --------------------------------------------

    function test_defaultCryptoAddress_resolvesPerSelection() public {
        assertEq(wallet.defaultCryptoAddress(), weth);

        vm.prank(ownerEOA);
        wallet.setDefaultCrypto(DefaultCrypto.BTC);
        assertEq(wallet.defaultCryptoAddress(), cbBTC);
    }

    function test_defaultCryptoAddress_revertsWhileSethUndeployed() public {
        vm.prank(ownerEOA);
        wallet.setDefaultCrypto(DefaultCrypto.SETH);

        // Preference is stored fine; only the resolution reverts until SETH is registered.
        assertEq(uint8(wallet.defaultCrypto()), uint8(DefaultCrypto.SETH));
        vm.expectRevert(AddressNotFound.selector);
        wallet.defaultCryptoAddress();

        // Once the wrapper is deployed and registered, resolution starts working.
        address seth = makeAddr("seth");
        vm.prank(admin);
        provider.registerName("SETH", seth);
        assertEq(wallet.defaultCryptoAddress(), seth);
    }

    function test_defaultStablecoinAddress_resolvesAllOptions() public {
        assertEq(wallet.defaultStablecoinAddress(), tgbp);

        vm.startPrank(ownerEOA);
        wallet.setDefaultStablecoin(DefaultStablecoin.USDC);
        assertEq(wallet.defaultStablecoinAddress(), usdc);

        wallet.setDefaultStablecoin(DefaultStablecoin.EURC);
        assertEq(wallet.defaultStablecoinAddress(), eurc);

        wallet.setDefaultStablecoin(DefaultStablecoin.DAI);
        assertEq(wallet.defaultStablecoinAddress(), dai);
        vm.stopPrank();
    }
}
