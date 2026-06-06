// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { ERC20 } from "@oz/contracts/token/ERC20/ERC20.sol";

/**
 * @title SETH | StabilityETH
 * @notice Bare-bones 1:100 wrapper between native ETH and SETH. Deposit ETH, mint SETH at 100:1; burn SETH, redeem ETH at 1:100.
 * @dev Genesis version: no fees, no cross-chain, no permit, no oracle. Reentrancy is handled via checks-effects-interactions —
 *      `_burn` debits the caller's SETH (and therefore their right to claim collateral) before the ETH transfer.
 */
contract SETH is ERC20 {
    /// @notice 100 SETH per 1 ETH; the only collateralization parameter
    uint256 public constant EXCHANGE_RATE = 100;

    event Deposit(address indexed dst, uint256 ethAmount, uint256 sethAmount);
    event Withdrawal(address indexed src, uint256 sethAmount, uint256 ethAmount);

    error InvalidAmount();
    error EthTransferFailed();

    constructor() ERC20("StabilityETH", "SETH") { }

    /// @notice Bare ETH transfers route into deposit() so the contract behaves like a wrapper for naive senders
    receive() external payable {
        deposit();
    }

    /**
     * @notice Mints SETH at a 100:1 ratio to ETH deposited
     */
    function deposit() public payable {
        if (msg.value == 0) revert InvalidAmount();

        uint256 sethAmount = msg.value * EXCHANGE_RATE;
        _mint(msg.sender, sethAmount);

        emit Deposit(msg.sender, msg.value, sethAmount);
    }

    /**
     * @notice Burns SETH and redeems ETH at a 1:100 ratio
     * @dev Rounds the burn down to the nearest multiple of EXCHANGE_RATE so the redeemed wei amount is exact;
     *      sub-EXCHANGE_RATE dust stays with the caller. Reverts if `sethAmount` is below one ETH-wei worth (100).
     */
    function withdraw(
        uint256 sethAmount
    ) external {
        if (sethAmount < EXCHANGE_RATE) revert InvalidAmount();

        // forge-lint: disable-next-line(divide-before-multiply) - intentional floor-rounding to a multiple of EXCHANGE_RATE
        uint256 amountToBurn = (sethAmount / EXCHANGE_RATE) * EXCHANGE_RATE;
        uint256 ethAmount = amountToBurn / EXCHANGE_RATE;

        _burn(msg.sender, amountToBurn);

        (bool success,) = msg.sender.call{ value: ethAmount }("");
        if (!success) revert EthTransferFailed();

        emit Withdrawal(msg.sender, amountToBurn, ethAmount);
    }

    // --------------------------------------------
    //  View helpers
    // --------------------------------------------

    /// @notice ETH collateral that backs the SETH supply
    function ethCollateral() external view returns (uint256) {
        return address(this).balance;
    }

    /// @notice Whether the contract holds enough ETH to fully redeem the current SETH supply at 1:100
    function isFullyBacked() external view returns (bool) {
        uint256 supply = totalSupply();
        if (supply == 0) return true;
        return address(this).balance * EXCHANGE_RATE >= supply;
    }
}
