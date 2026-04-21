// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { AccessControl } from "@core/AccessControl.sol";
import { Oracle } from "@core/Oracle.sol";
import { RateLimit } from "@core/RateLimit.sol";
import { Matchweek } from "@core/types/FixtureTypes.sol";

contract Matchweeks is AccessControl, RateLimit, Oracle {
    string public getMatchweeksScript;
    uint256 public matchweekCount;

    mapping(uint256 matchweekNumber => Matchweek matchweek) public getMatchweek;

    constructor(address addressProvider_) AccessControl(addressProvider_) RateLimit(24 hours) { }

    function scan() external rateLimited {
        // TODO: Implement
    }

    function add(Matchweek memory matchweek) external onlyOrchestrator {
        getMatchweek[matchweek.matchweekNumber] = matchweek;
        matchweekCount++;
    }

    function remove(Matchweek memory matchweek) external onlyOrchestrator {
        delete getMatchweek[matchweek.matchweekNumber];
        matchweekCount--;
    }
}