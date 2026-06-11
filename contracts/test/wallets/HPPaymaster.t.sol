// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { IPaymaster06 } from "@account-abstraction/legacy/v06/IPaymaster06.sol";
import { UserOperation06 } from "@account-abstraction/legacy/v06/UserOperation06.sol";

import { HPPaymaster } from "@src/wallets/HPPaymaster.sol";
import { HPSmartWallet } from "@src/wallets/HPSmartWallet.sol";
import { HPSmartWalletFactory } from "@src/wallets/HPSmartWalletFactory.sol";

import { WalletTestBase } from "./WalletTestBase.sol";

/// @dev Minimal v0.6 EntryPoint stand-in: real deposit/stake bookkeeping, no userOp pipeline.
contract MockEntryPoint {
    mapping(address account => uint256 amount) public balanceOf;

    uint256 public stake;
    uint32 public lastUnstakeDelaySec;
    bool public stakeUnlocked;

    function depositTo(address account) external payable {
        balanceOf[account] += msg.value;
    }

    function addStake(uint32 unstakeDelaySec) external payable {
        stake += msg.value;
        lastUnstakeDelaySec = unstakeDelaySec;
        stakeUnlocked = false;
    }

    function unlockStake() external {
        stakeUnlocked = true;
    }

    function withdrawStake(address payable to) external {
        uint256 amount = stake;
        stake = 0;
        (bool ok,) = to.call{ value: amount }("");
        require(ok, "stake transfer failed");
    }

    function withdrawTo(address payable to, uint256 amount) external {
        balanceOf[msg.sender] -= amount;
        (bool ok,) = to.call{ value: amount }("");
        require(ok, "withdraw transfer failed");
    }
}

contract HPPaymasterTest is WalletTestBase {
    MockEntryPoint internal mockEntryPoint;
    HPPaymaster internal paymaster;
    HPSmartWallet internal wallet;

    address internal funder = makeAddr("funder");

    event GasCreditDeposited(address indexed funder, address indexed wallet, uint256 amount);
    event GasCreditUsed(address indexed wallet, uint256 amount);
    event SurplusWithdrawn(address indexed to, uint256 amount);

    function setUp() public override {
        super.setUp();

        mockEntryPoint = new MockEntryPoint();
        paymaster = new HPPaymaster(address(provider), address(mockEntryPoint));

        vm.prank(admin);
        provider.registerName("PAYMASTER", address(paymaster));

        wallet = _createWallet(ownerEOA, 0);
        vm.deal(funder, 100 ether);

        // Deterministic fee environment: basefee 0 so the userOp fee rate resolves to maxPriorityFeePerGas.
        vm.fee(0);
    }

    function _sponsoredOp(address sender, uint256 maxFeePerGas) internal pure returns (UserOperation06 memory op) {
        op = _baseUserOp(sender, 0);
        op.maxFeePerGas = maxFeePerGas;
        op.maxPriorityFeePerGas = maxFeePerGas;
        op.paymasterAndData = "";
    }

    /// @dev Reservation for `maxCost` at `maxFeePerGas`, including the postOp margin.
    function _reserved(uint256 maxCost, uint256 maxFeePerGas) internal view returns (uint256) {
        return maxCost + paymaster.POST_OP_GAS() * maxFeePerGas;
    }

    function _validate(address sender, uint256 maxFeePerGas, uint256 maxCost) internal returns (bytes memory context) {
        UserOperation06 memory op = _sponsoredOp(sender, maxFeePerGas);
        vm.prank(address(mockEntryPoint));
        (context,) = paymaster.validatePaymasterUserOp(op, bytes32(0), maxCost);
    }

    // --------------------------------------------
    //  Construction / wiring
    // --------------------------------------------

    function test_constructor_revertsForZeroEntryPoint() public {
        vm.expectRevert(HPPaymaster.ZeroEntryPoint.selector);
        new HPPaymaster(address(provider), address(0));
    }

    function test_constructor_cachesFactory() public view {
        assertEq(address(paymaster.walletFactory()), address(factory));
    }

    function test_syncFactory_followsAddressProvider() public {
        HPSmartWalletFactory newFactory = new HPSmartWalletFactory(address(walletImplementation), address(provider));
        vm.prank(admin);
        provider.setName("WALLET_FACTORY", address(newFactory));

        paymaster.syncFactory();

        assertEq(address(paymaster.walletFactory()), address(newFactory));
    }

    // --------------------------------------------
    //  Funding
    // --------------------------------------------

    function test_depositFor_creditsWalletAndFundsEntryPoint() public {
        vm.expectEmit(true, true, false, true, address(paymaster));
        emit GasCreditDeposited(funder, address(wallet), 1 ether);

        vm.prank(funder);
        paymaster.depositFor{ value: 1 ether }(address(wallet));

        assertEq(paymaster.gasCredit(address(wallet)), 1 ether);
        assertEq(paymaster.totalGasCredit(), 1 ether);
        assertEq(mockEntryPoint.balanceOf(address(paymaster)), 1 ether);
    }

    function test_depositFor_worksForCounterfactualWallet() public {
        address counterfactual = factory.getAddress(_singleOwner(makeAddr("futureUser")), 0);

        vm.prank(funder);
        paymaster.depositFor{ value: 0.5 ether }(counterfactual);

        assertEq(paymaster.gasCredit(counterfactual), 0.5 ether);
    }

    function test_depositFor_revertsForZeroWalletOrValue() public {
        vm.prank(funder);
        vm.expectRevert(HPPaymaster.ZeroWallet.selector);
        paymaster.depositFor{ value: 1 ether }(address(0));

        vm.prank(funder);
        vm.expectRevert(HPPaymaster.ZeroDeposit.selector);
        paymaster.depositFor(address(wallet));
    }

    // --------------------------------------------
    //  validatePaymasterUserOp (reserves credit)
    // --------------------------------------------

    function test_validate_acceptsAndReservesForFundedWallet() public {
        vm.prank(funder);
        paymaster.depositFor{ value: 1 ether }(address(wallet));

        uint256 maxCost = 0.01 ether;
        uint256 reserved = _reserved(maxCost, 1 gwei);

        UserOperation06 memory op = _sponsoredOp(address(wallet), 1 gwei);
        vm.prank(address(mockEntryPoint));
        (bytes memory context, uint256 validationData) = paymaster.validatePaymasterUserOp(op, bytes32(0), maxCost);

        assertEq(validationData, 0);
        (address s, uint256 r,,) = abi.decode(context, (address, uint256, uint256, uint256));
        assertEq(s, address(wallet));
        assertEq(r, reserved);

        // Credit is debited at validation time (the reservation).
        assertEq(paymaster.gasCredit(address(wallet)), 1 ether - reserved);
        assertEq(paymaster.totalGasCredit(), 1 ether - reserved);
    }

    function test_validate_revertsWhenNotEntryPoint() public {
        UserOperation06 memory op = _sponsoredOp(address(wallet), 1 gwei);

        vm.expectRevert(HPPaymaster.NotEntryPoint.selector);
        paymaster.validatePaymasterUserOp(op, bytes32(0), 0.01 ether);
    }

    function test_validate_revertsForNonHPWallet() public {
        address stranger = makeAddr("strangerWallet");
        vm.prank(funder);
        paymaster.depositFor{ value: 1 ether }(stranger);

        UserOperation06 memory op = _sponsoredOp(stranger, 1 gwei);

        vm.prank(address(mockEntryPoint));
        vm.expectRevert(abi.encodeWithSelector(HPPaymaster.WalletNotRegistered.selector, stranger));
        paymaster.validatePaymasterUserOp(op, bytes32(0), 0.01 ether);
    }

    function test_validate_revertsOnInsufficientCredit() public {
        uint256 maxCost = 0.01 ether;
        uint256 reserved = _reserved(maxCost, 1 gwei);

        vm.prank(funder);
        paymaster.depositFor{ value: reserved - 1 }(address(wallet));

        UserOperation06 memory op = _sponsoredOp(address(wallet), 1 gwei);
        vm.prank(address(mockEntryPoint));
        vm.expectRevert(
            abi.encodeWithSelector(HPPaymaster.InsufficientGasCredit.selector, address(wallet), reserved - 1, reserved)
        );
        paymaster.validatePaymasterUserOp(op, bytes32(0), maxCost);
    }

    /// @dev Audit #84970: a second validation in the same batch cannot reuse already-reserved credit.
    function test_validate_batchReservationPreventsOverspend() public {
        uint256 maxCost = 0.01 ether;
        uint256 reserved = _reserved(maxCost, 1 gwei);

        // Fund enough for one operation plus a sliver — not two.
        vm.prank(funder);
        paymaster.depositFor{ value: reserved + 1 }(address(wallet));

        // First op validates and reserves.
        _validate(address(wallet), 1 gwei, maxCost);
        assertEq(paymaster.gasCredit(address(wallet)), 1);

        // Second op in the same batch is rejected: the credit was already reserved.
        UserOperation06 memory op2 = _sponsoredOp(address(wallet), 1 gwei);
        vm.prank(address(mockEntryPoint));
        vm.expectRevert(
            abi.encodeWithSelector(HPPaymaster.InsufficientGasCredit.selector, address(wallet), 1, reserved)
        );
        paymaster.validatePaymasterUserOp(op2, bytes32(0), maxCost);
    }

    // --------------------------------------------
    //  postOp settlement (refund + correct fee rate)
    // --------------------------------------------

    function test_postOp_chargesActualCostAndRefundsRemainder() public {
        vm.prank(funder);
        paymaster.depositFor{ value: 1 ether }(address(wallet));

        uint256 maxCost = 0.01 ether;
        bytes memory context = _validate(address(wallet), 1 gwei, maxCost);

        uint256 actualGasCost = 0.001 ether;
        uint256 expectedCharge = actualGasCost + paymaster.POST_OP_GAS() * 1 gwei; // basefee 0 => fee rate = 1 gwei

        vm.expectEmit(true, false, false, true, address(paymaster));
        emit GasCreditUsed(address(wallet), expectedCharge);

        vm.prank(address(mockEntryPoint));
        paymaster.postOp(IPaymaster06.PostOpMode.opSucceeded, context, actualGasCost);

        // Net effect across validate + postOp is exactly the actual charge.
        assertEq(paymaster.gasCredit(address(wallet)), 1 ether - expectedCharge);
        assertEq(paymaster.totalGasCredit(), 1 ether - expectedCharge);
    }

    /// @dev Audit #84971: the postOp margin is priced at the userOp fee rate, never at tx.gasprice.
    function test_postOp_usesUserOpFeeRateNotTxGasPrice() public {
        vm.prank(funder);
        paymaster.depositFor{ value: 5 ether }(address(wallet));

        uint256 maxFee = 100 gwei;
        uint256 maxCost = 0.01 ether;
        bytes memory context = _validate(address(wallet), maxFee, maxCost);

        // Bundler submits at a far lower tx.gasprice; accounting must ignore it.
        vm.txGasPrice(1 gwei);
        uint256 actualGasCost = 0.003 ether;
        uint256 expectedCharge = actualGasCost + paymaster.POST_OP_GAS() * maxFee; // fee rate = min(maxFee, maxPriority+basefee) = 100 gwei

        vm.prank(address(mockEntryPoint));
        paymaster.postOp(IPaymaster06.PostOpMode.opSucceeded, context, actualGasCost);

        // Charged at the (higher) userOp fee rate, matching what the EntryPoint deducts — no shared-deposit
        // deficit. Had it used tx.gasprice (1 gwei) the charge would have been far smaller.
        assertEq(paymaster.gasCredit(address(wallet)), 5 ether - expectedCharge);
        assertEq(paymaster.totalGasCredit(), 5 ether - expectedCharge);
    }

    /// @dev Safety net: a context whose reservation is below the computed charge clamps without underflow.
    function test_postOp_clampsChargeToReservation() public {
        vm.prank(funder);
        paymaster.depositFor{ value: 1 ether }(address(wallet));

        // Hand-crafted context with a tiny reservation and a huge actual cost.
        bytes memory context = abi.encode(address(wallet), uint256(0.0001 ether), uint256(1 gwei), uint256(1 gwei));

        vm.prank(address(mockEntryPoint));
        paymaster.postOp(IPaymaster06.PostOpMode.opSucceeded, context, 1 ether);

        // charge clamped to the reservation => refund is zero, no revert, credit unchanged by this call.
        assertEq(paymaster.gasCredit(address(wallet)), 1 ether);
    }

    function test_postOp_revertsWhenNotEntryPoint() public {
        bytes memory context = abi.encode(address(wallet), uint256(1), uint256(1 gwei), uint256(1 gwei));
        vm.expectRevert(HPPaymaster.NotEntryPoint.selector);
        paymaster.postOp(IPaymaster06.PostOpMode.opSucceeded, context, 1);
    }

    /// @dev Audit #85730: an unbounded maxPriorityFeePerGas must not overflow/revert the settlement hook.
    function test_postOp_doesNotRevertOnUnboundedPriorityFee() public {
        vm.fee(1); // basefee >= 1 so a checked add would overflow
        vm.prank(funder);
        paymaster.depositFor{ value: 1 ether }(address(wallet));

        // reserved sized off a small maxFeePerGas; maxPriorityFeePerGas pushed to the max.
        bytes memory context =
            abi.encode(address(wallet), uint256(0.01 ether), uint256(1 gwei), type(uint256).max);

        // Must settle without reverting (unchecked wrap mirrors the EntryPoint's own gas-price math).
        vm.prank(address(mockEntryPoint));
        paymaster.postOp(IPaymaster06.PostOpMode.opSucceeded, context, 0.001 ether);
    }

    // --------------------------------------------
    //  Stake / surplus administration
    // --------------------------------------------

    function test_stakeManagement_adminOnlyAndForwarded() public {
        vm.deal(admin, 10 ether);

        vm.prank(admin);
        paymaster.addStake{ value: 2 ether }(86_400);
        assertEq(mockEntryPoint.stake(), 2 ether);
        assertEq(mockEntryPoint.lastUnstakeDelaySec(), 86_400);

        vm.prank(admin);
        paymaster.unlockStake();
        assertTrue(mockEntryPoint.stakeUnlocked());

        address payable treasury = payable(makeAddr("treasury"));
        vm.prank(admin);
        paymaster.withdrawStake(treasury);
        assertEq(treasury.balance, 2 ether);
    }

    function test_stakeManagement_revertsForNonAdmin() public {
        address stranger = makeAddr("stranger");
        vm.deal(stranger, 1 ether);

        vm.startPrank(stranger);
        vm.expectRevert(HPPaymaster.NotAdmin.selector);
        paymaster.addStake{ value: 1 ether }(86_400);

        vm.expectRevert(HPPaymaster.NotAdmin.selector);
        paymaster.unlockStake();

        vm.expectRevert(HPPaymaster.NotAdmin.selector);
        paymaster.withdrawStake(payable(stranger));

        vm.expectRevert(HPPaymaster.NotAdmin.selector);
        paymaster.withdrawSurplus(payable(stranger), 1);
        vm.stopPrank();
    }

    function test_withdrawSurplus_onlyAboveUserCredits() public {
        vm.prank(funder);
        paymaster.depositFor{ value: 1 ether }(address(wallet));

        // Run a full cycle; the consumed charge leaves the EntryPoint deposit above totalGasCredit (the mock
        // doesn't actually pay gas), which is exactly the withdrawable surplus.
        bytes memory context = _validate(address(wallet), 1 gwei, 0.6 ether);
        vm.prank(address(mockEntryPoint));
        paymaster.postOp(IPaymaster06.PostOpMode.opSucceeded, context, 0.5 ether);

        uint256 s = paymaster.surplus();
        assertGt(s, 0);

        address payable treasury = payable(makeAddr("treasury"));
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(HPPaymaster.WithdrawExceedsSurplus.selector, s + 1, s));
        paymaster.withdrawSurplus(treasury, s + 1);

        vm.prank(admin);
        paymaster.withdrawSurplus(treasury, s);
        assertEq(treasury.balance, s);
        assertEq(paymaster.surplus(), 0);
    }

    // --------------------------------------------
    //  End-to-end sponsorship shape
    // --------------------------------------------

    function test_fullSponsorshipFlow() public {
        vm.prank(funder);
        paymaster.depositFor{ value: 0.1 ether }(address(wallet));

        bytes memory context = _validate(address(wallet), 1 gwei, 0.005 ether);

        uint256 actualGasCost = 0.002 ether;
        vm.prank(address(mockEntryPoint));
        paymaster.postOp(IPaymaster06.PostOpMode.opSucceeded, context, actualGasCost);

        uint256 charged = actualGasCost + paymaster.POST_OP_GAS() * 1 gwei;
        assertEq(paymaster.gasCredit(address(wallet)), 0.1 ether - charged);

        // Remaining credit still sponsors future ops.
        _validate(address(wallet), 1 gwei, 0.005 ether);
        assertEq(paymaster.gasCredit(address(wallet)), 0.1 ether - charged - _reserved(0.005 ether, 1 gwei));
    }
}
