// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import { Club, Position } from "@core/types/AssetTypes.sol";

enum PlayerStatus { Inactive, Pending, Active }

struct SeasonMinutes {
    uint16 seasonStart;
    uint256 seasonMinutes;
}

struct PositionMinutes {
    Position position;
    uint256 positionMinutes;
}

struct Player {
    address tokenAddress;
    uint256 playerId;
    string name;
    string shortName;
    Club club;
    Position position;
    PositionMinutes[] positionMinutes;
    uint256 birthDate;
    SeasonMinutes[] totalMinutes;
    PlayerStatus status;
}