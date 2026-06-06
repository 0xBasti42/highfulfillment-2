// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

enum Status { Pending, Active, Completed }

struct Matchweek {
    uint16 seasonStartYear;
    uint8 matchweekNumber;
    Status status;
    Fixture[] fixtures;
    uint256 startTime;
    uint256 endTime;
}

enum EventType {
    Goal,
    Assist,
    YellowCard,
    RedCard,
    Substitution,
    Penalty,
    PenaltyMissed
}

struct Event {
    EventType eventType;
    string personId;
    uint256 eventTime;
}

struct Fixture {
    uint16 seasonStartYear;
    uint8 matchweekNumber;
    uint256 fixtureId;
    string fixtureName;
    string homeShorthand;
    uint16 homeScore;
    Event[] homeEvents;
    string awayShorthand;
    uint16 awayScore;
    Event[] awayEvents;
    uint256 startTime;
    uint256 endTime;
    Status status; // Pending, Active, Completed
}