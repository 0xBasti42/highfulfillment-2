// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";

import { AddressProvider } from "@src/AddressProvider.sol";
import { HPPaymaster } from "@src/wallets/HPPaymaster.sol";
import { HPSmartWallet } from "@src/wallets/HPSmartWallet.sol";
import { HPSmartWalletFactory } from "@src/wallets/HPSmartWalletFactory.sol";

/// @title DeployWalletFactory
/// @notice Deploys the ERC-4337 v0.6 account-abstraction core for HighPotential: the wallet implementation,
///         the CREATE2 factory (also the legitimacy oracle), and the deposit paymaster — then registers them
///         in the AddressProvider and stakes the paymaster so it can sponsor user operations.
/// @dev Ordering is load-bearing:
///        1. AddressProvider must exist first (everything resolves through it).
///        2. The wallet implementation must be deployed before the factory (the factory's constructor reverts
///           if the implementation has no code).
///        3. WALLET_FACTORY must be registered before the paymaster is deployed: the paymaster's constructor
///           calls `syncFactory()`, which resolves WALLET_FACTORY and reverts if it is unset.
///        4. The paymaster must be staked (EntryPoint stake) before it can read sender-associated storage in
///           validation under ERC-7562.
///
///      The deposit layer (HPDepositConverter + HPDepositRouter) is intentionally NOT deployed here — it
///      depends on live Aerodrome/PSM3 liquidity and is a separate script. This script is everything needed
///      to deploy + sign + sponsor HPSmartWallets through the Turnkey/Pimlico flow.
///
///      Config (env vars, all optional with sane defaults):
///        ADDRESS_PROVIDER        - reuse an existing provider; if unset, a fresh one is deployed with the
///                                  broadcaster as admin. (Reuse requires the broadcaster to hold the
///                                  provider's DEFAULT_ADMIN_ROLE + ADDRESS_MANAGER_ROLE.)
///        ENTRYPOINT              - ERC-4337 v0.6 EntryPoint. Defaults to the canonical cross-chain address.
///        PAYMASTER_STAKE_WEI     - ETH staked into the EntryPoint for the paymaster (required to be > 0 for a
///                                  functional paymaster). Default 0.01 ether.
///        PAYMASTER_UNSTAKE_DELAY - seconds before staked ETH can be withdrawn. Default 1 day.
///        Token keys (register only if provided non-zero): WETH, CBBTC, SETH, TGBP, USDC, EURC, USDS.
contract DeployWalletFactory is Script {
    /// @dev Canonical ERC-4337 v0.6 EntryPoint (same address on Base mainnet and Base Sepolia). Matches the
    ///      hardcoded `HPSmartWallet.entryPoint()`.
    address internal constant DEFAULT_ENTRYPOINT = 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789;

    function run() external {
        address entryPoint = vm.envOr("ENTRYPOINT", DEFAULT_ENTRYPOINT);
        uint256 stakeWei = vm.envOr("PAYMASTER_STAKE_WEI", uint256(0.01 ether));
        uint32 unstakeDelay = uint32(vm.envOr("PAYMASTER_UNSTAKE_DELAY", uint256(1 days)));
        address existingProvider = vm.envOr("ADDRESS_PROVIDER", address(0));

        vm.startBroadcast();
        address deployer = msg.sender;

        // 1. AddressProvider (reuse or deploy fresh with the broadcaster as admin).
        AddressProvider provider =
            existingProvider == address(0) ? new AddressProvider(deployer) : AddressProvider(payable(existingProvider));

        // 2. Wallet implementation (locks itself against direct initialization in its constructor).
        HPSmartWallet implementation = new HPSmartWallet(address(provider));

        // 3. Factory + register as the legitimacy oracle the paymaster reads.
        HPSmartWalletFactory factory = new HPSmartWalletFactory(address(implementation), address(provider));
        provider.registerName("WALLET_FACTORY", address(factory));

        // 4. Paymaster (constructor resolves WALLET_FACTORY, so step 3 must precede this) + register.
        HPPaymaster paymaster = new HPPaymaster(address(provider), entryPoint);
        provider.registerName("PAYMASTER", address(paymaster));

        // 5. Stake the paymaster so it can reference sender-associated storage during validation.
        if (stakeWei != 0) {
            paymaster.addStake{ value: stakeWei }(unstakeDelay);
        }

        // 6. Optional token-key registration (skip any left unset). Enables the wallet's
        //    `defaultCryptoAddress()` / `defaultStablecoinAddress()` resolution helpers.
        _registerIfSet(provider, "WETH");
        _registerIfSet(provider, "CBBTC");
        _registerIfSet(provider, "SETH");
        _registerIfSet(provider, "TGBP");
        _registerIfSet(provider, "USDC");
        _registerIfSet(provider, "EURC");
        _registerIfSet(provider, "USDS");

        vm.stopBroadcast();

        console2.log("=== HighPotential AA core deployed ===");
        console2.log("AddressProvider:    ", address(provider));
        console2.log("WalletImpl:         ", address(implementation));
        console2.log("WalletFactory:      ", address(factory));
        console2.log("Paymaster:          ", address(paymaster));
        console2.log("EntryPoint:         ", entryPoint);
        console2.log("Paymaster staked:   ", stakeWei);
        console2.log("Factory initHash:   ");
        console2.logBytes32(factory.initCodeHash());
    }

    /// @dev Registers `name` -> the address in env var `name` (e.g. WETH=0x...), upserting so the script is
    ///      safe to re-run and works against a shared provider. Zero/unset addresses are skipped.
    function _registerIfSet(AddressProvider provider, string memory name) internal {
        address token = vm.envOr(name, address(0));
        if (token != address(0)) {
            provider.setName(name, token);
            console2.log(string.concat("Registered ", name, ":"), token);
        }
    }
}
