// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

/// @title IHPWalletFactory
/// @notice Minimal view surface the paymaster relies on: a wallet-keyed legitimacy flag.
/// @dev `isHPWallet` is keyed by the CREATE2 wallet address (unforgeable), so it is safe as the paymaster's
///      "is this a real HP wallet" oracle. Reading `isHPWallet[sender]` during validation is permitted under
///      ERC-7562 because the slot is sender-associated.
interface IHPWalletFactory {
    function isHPWallet(address wallet) external view returns (bool);
}
