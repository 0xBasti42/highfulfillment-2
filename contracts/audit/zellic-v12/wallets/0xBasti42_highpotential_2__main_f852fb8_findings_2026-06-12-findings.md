# Audited by [V12](https://v12.sh/)

The only autonomous auditor that finds critical bugs. Not all audits are equal, so stop paying for bad ones. Just use V12. No calls, demos, or intros.

# Residual Ether Claimable
**#85911**
- Severity: Low
- Validity: Invalid

## Source locations

### `contracts/src/wallets/HPDepositConverter.sol` (2 locations)
#### Lines 75-76 — _The converter can receive native ETH without restricting the sender._

```
    /// @dev Receives native ETH from Aerodrome's `swapExactTokensForETH` unwrap.
    receive() external payable { }
```

⋯
#### Lines 122-128 — _The conversion result is the full converter balance, which is forwarded to the router._

```
        // Forward the full balance (not just this conversion's output) so no ETH ever rests here.
        // Stray donations end up as extra gas credit for the depositing wallet — harmless.
        ethOut = address(this).balance;
        if (ethOut != 0) {
            (bool ok,) = msg.sender.call{ value: ethOut }("");
            if (!ok) revert EthTransferFailed();
        }
```

### `contracts/src/wallets/HPDepositRouter.sol` (2 locations)
#### Lines 111-118 — _Any user can call the token deposit path and choose the destination wallet for a supported token._

```
    function depositToken(address token, uint256 amount, address wallet, uint256 minEthOut) external {
        if (wallet == address(0)) revert ZeroWallet();
        if (amount == 0) revert ZeroAmount();

        TokenClass class = _classify(token);

        token.safeTransferFrom(msg.sender, address(this), amount);

```

⋯
#### Lines 129-148 — _The router calls the converter, measures its own ETH balance delta, and deposits that ETH for the chosen wallet._

```
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
```

### `contracts/src/wallets/HPPaymaster.sol`
#### Lines 101-110 — _The paymaster credits the specified wallet with all ETH sent by the router._

```
    function depositFor(address wallet) external payable {
        if (wallet == address(0)) revert ZeroWallet();
        if (msg.value == 0) revert ZeroDeposit();

        gasCredit[wallet] += msg.value;
        totalGasCredit += msg.value;

        entryPoint.depositTo{ value: msg.value }(address(this));

        emit GasCreditDeposited(msg.sender, wallet, msg.value);
```

## Description

`HPDepositConverter` accepts native ETH through an unrestricted `receive()` function and does not maintain per-call accounting for ETH that was present before a conversion. At the end of `convertToEth`, it sets `ethOut` to `address(this).balance` and forwards that full balance to the registered router rather than only the ETH produced by the current PSM/Aerodrome path. Any external user can then trigger the router’s `depositToken` path for an enabled swap-class token and choose the wallet that receives the resulting paymaster credit. As a result, residual ETH that reaches the converter through a mistaken direct transfer or forced transfer is swept into the next depositor’s wallet credit instead of remaining recoverable or attributable to its sender.

## Root cause

`convertToEth` uses the converter’s whole ETH balance as per-call output instead of tracking the ETH balance before and after the current conversion. The unrestricted `receive()` function makes pre-existing ETH possible, and the router later trusts the returned balance delta as credit for the caller-selected wallet.

## Impact

An attacker can convert any residual ETH sitting in the converter into gas credit for an HP wallet they control by making a minimal routed token deposit. This does not drain ordinary in-flight deposits, but it captures unintended ETH balances and makes stale converter balance part of another user’s credited output.
