// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { IEntryPoint } from "@account-abstraction/legacy/v06/IEntryPoint06.sol";
import { IPaymaster06 } from "@account-abstraction/legacy/v06/IPaymaster06.sol";
import { UserOperation06 } from "@account-abstraction/legacy/v06/UserOperation06.sol";

import { AddressBook } from "@core/AddressBook.sol";

import { IHPWalletFactory } from "./interfaces/IHPWalletFactory.sol";

/// @title HPPaymaster
/// @notice ERC-4337 v0.6 deposit paymaster: sponsors gas for HP wallets out of per-wallet ETH credits. Credits
///         are funded via `depositFor` (deposit-skim flow, deposit router, or treasury top-up) and the backing
///         ETH lives as this contract's deposit inside the EntryPoint.
/// @dev Validation-phase rules (ERC-7562), all relying on this paymaster being STAKED:
///      - `walletFactory.isHPWallet[sender]` is sender-associated storage in another contract — allowed.
///      - `gasCredit[sender]` (sender-associated) and `totalGasCredit` (own storage) are written during
///        validation to *reserve* the operation's cost; a staked entity may write its own storage.
///      - The AddressProvider must NOT be read during validation, so the factory address is cached in this
///        contract's storage and refreshed permissionlessly via `syncFactory`.
///      Deployment order: factory -> paymaster (constructor resolves WALLET_FACTORY), then `addStake` and an
///      initial `depositFor`/EntryPoint deposit before the first sponsored op.
contract HPPaymaster is IPaymaster06, AddressBook {
    // --------------------------------------------
    //  Configuration
    // --------------------------------------------

    /// @dev Gas margin charged on top of `actualGasCost` to cover the `postOp` call itself.
    uint256 public constant POST_OP_GAS = 45_000;

    IEntryPoint public immutable entryPoint;

    /// @dev Cached so validation never touches AddressProvider storage (see contract natspec).
    IHPWalletFactory public walletFactory;

    mapping(address wallet => uint256 creditWei) public gasCredit;

    /// @dev Sum of all outstanding credits; invariant `entryPoint.balanceOf(this) >= totalGasCredit` is
    ///      preserved because each operation reserves its full cost in validation before any settlement.
    uint256 public totalGasCredit;

    // --------------------------------------------
    //  Events and Errors
    // --------------------------------------------

    event GasCreditDeposited(address indexed funder, address indexed wallet, uint256 amount);
    event GasCreditUsed(address indexed wallet, uint256 amount);
    event FactorySynced(address indexed walletFactory);
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
        syncFactory();
    }

    /// @notice Re-resolves the wallet factory from the AddressProvider. Permissionless: the provider is the
    ///         source of truth and its mutations are already role-gated.
    function syncFactory() public {
        walletFactory = IHPWalletFactory(_getAddress(_addressKey("WALLET_FACTORY")));
        emit FactorySynced(address(walletFactory));
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
    }

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
