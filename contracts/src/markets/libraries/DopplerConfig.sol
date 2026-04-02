// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

library DopplerConfig {
    uint256 constant TOTAL_SUPPLY = 22_000_000 ether;
    uint256 constant NUM_TOKENS_TO_SELL = 12_000_000 ether;

    address constant NUMERAIRE = address(0);

    uint256 constant MINIMUM_PROCEEDS = 0;
    uint256 constant MAXIMUM_PROCEEDS = 0;
    uint256 constant STARTING_TIME = 0;
    uint256 constant ENDING_TIME = 0;
    int24 constant STARTING_TICK = 0;
    int24 constant ENDING_TICK = 0;
    uint256 constant EPOCH_LENGTH = 0;
    int24 constant GAMMA = 0;
    bool constant IS_TOKEN0 = false;
    uint256 constant NUM_PD_SLUGS = 0;
    uint24 constant LP_FEE = 0;

    int24 constant TICK_SPACING = 60;
}