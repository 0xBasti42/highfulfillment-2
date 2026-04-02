// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { Doppler } from "@doppler/initializers/Doppler.sol";
import { ReentrancyGuardTransient } from "@oz/contracts/utils/ReentrancyGuardTransient.sol";
import { ImmutableAddressProvider } from "@base/ImmutableAddressProvider.sol";
import { DynamicFee } from "@base/DynamicFee.sol";

/**
 * @title DopplerHook | HighPotential
 * @author Isla Labs (Tom Jarvis | 0xBasti42)
 * @notice Bonding curve hook for UniswapV4
 * @custom:experimental DeFi markets covering EPL, NFL, NBA, and more. | Learn more at https://docs.highpotential.io/
 * @custom:security-contact security@islalabs.co
 */
contract DopplerHook is Doppler, ReentrancyGuardTransient, ImmutableAddressProvider, DynamicFee { }
