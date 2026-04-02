// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

enum Status { Pending, Active, Completed }

struct Matchweek {
    uint8 matchweekNumber;
    uint256 startTime;
    uint256 endTime;
    Status status;
}

struct Fixture {
    uint256 fixtureId;
    string fixtureName;
    uint8 matchweekNumber;
    string homeShorthand;
    string awayShorthand;
    uint256 startTime;
    Status status;
}