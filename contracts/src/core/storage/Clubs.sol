// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { AccessControl } from "@core/AccessControl.sol";
import { Club } from "@core/types/AssetTypes.sol";

contract Clubs is AccessControl {
    uint256 public clubCount;

    mapping(string shorthand => Club club) public getClub;
    mapping(string shorthand => uint256 clubId) public getClubId;

    constructor(address addressProvider_) AccessControl(addressProvider_) { }

    function add(Club memory club) external onlyOrchestrator {
        getClub[club.shorthand] = club;
        getClubId[club.shorthand] = club.clubId;
        clubCount++;
    }

    function remove(Club memory club) external onlyOrchestrator {
        delete getClub[club.shorthand];
        delete getClubId[club.shorthand];
        clubCount--;
    }
}