// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { Test } from "forge-std/Test.sol";

import { UserOperation06 } from "@account-abstraction/legacy/v06/UserOperation06.sol";

import { AddressProvider } from "@src/AddressProvider.sol";
import { HPSmartWallet } from "@src/wallets/HPSmartWallet.sol";
import { HPSmartWalletFactory } from "@src/wallets/HPSmartWalletFactory.sol";

/// @notice Shared harness: AddressProvider with token keys, wallet implementation, and factory wired exactly as
///         they would be on Base (SETH key intentionally left unset until its wrapper is deployed). The factory
///         is also the wallet-legitimacy oracle; there is no separate registry.
abstract contract WalletTestBase is Test {
    AddressProvider internal provider;
    HPSmartWallet internal walletImplementation;
    HPSmartWalletFactory internal factory;

    address internal admin = makeAddr("admin");
    address internal entryPointAddr = 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789;

    address internal ownerEOA;
    uint256 internal ownerPk;

    address internal cbBTC = makeAddr("cbBTC");
    address internal weth = makeAddr("weth");
    address internal tgbp = makeAddr("tgbp");
    address internal usdc = makeAddr("usdc");
    address internal eurc = makeAddr("eurc");
    address internal dai = makeAddr("dai");

    function setUp() public virtual {
        (ownerEOA, ownerPk) = makeAddrAndKey("ownerEOA");

        provider = new AddressProvider(admin);

        vm.startPrank(admin);
        provider.registerName("CBBTC", cbBTC);
        provider.registerName("WETH", weth);
        provider.registerName("TGBP", tgbp);
        provider.registerName("USDC", usdc);
        provider.registerName("EURC", eurc);
        provider.registerName("DAI", dai);
        vm.stopPrank();

        walletImplementation = new HPSmartWallet(address(provider));
        factory = new HPSmartWalletFactory(address(walletImplementation), address(provider));

        vm.prank(admin);
        provider.registerName("WALLET_FACTORY", address(factory));
    }

    // --------------------------------------------
    //  Helpers
    // --------------------------------------------

    function _singleOwner(address owner) internal pure returns (bytes[] memory owners) {
        owners = new bytes[](1);
        owners[0] = abi.encode(owner);
    }

    function _createWallet(address owner, uint256 nonce) internal returns (HPSmartWallet) {
        return factory.createAccount(_singleOwner(owner), nonce);
    }

    /// @dev 65-byte ECDSA signature wrapped in the wallet's `SignatureWrapper` envelope.
    function _eoaSignature(uint256 pk, bytes32 digest, uint256 ownerIndex) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encode(HPSmartWallet.SignatureWrapper(ownerIndex, abi.encodePacked(r, s, v)));
    }

    function _baseUserOp(address sender, uint256 nonce) internal pure returns (UserOperation06 memory op) {
        op.sender = sender;
        op.nonce = nonce;
        op.initCode = "";
        op.callData = "";
        op.callGasLimit = 1_000_000;
        op.verificationGasLimit = 1_000_000;
        op.preVerificationGas = 100_000;
        op.maxFeePerGas = 1 gwei;
        op.maxPriorityFeePerGas = 1 gwei;
        op.paymasterAndData = "";
        op.signature = "";
    }
}
