// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

struct PPM {
    address token;
    address vault;
    Coefficients coefficients;
    uint256 prevTotal;
    uint256 latestTotal;
}

// --------------------------------------------
//  Global Coefficients
// --------------------------------------------

struct Coefficients {
    GkCoeff gkCoeff;
    WdeDefCoeff wdeDefCoeff;
    CtrDefCoeff ctrDefCoeff;
    DefMidCoeff defMidCoeff;
    WdeMidCoeff wdeMidCoeff;
    AttMidCoeff attMidCoeff;
    WdeAttCoeff wdeAttCoeff;
    CtrAttCoeff ctrAttCoeff;
    uint256 prevTotal;
    uint256 latestTotal;
}

// --------------------------------------------
//  Individual Coefficients
// --------------------------------------------

struct GkCoeff {
    Datapoint distribution;
    Datapoint saves;
    Datapoint sweeps;
    Datapoint claims;
    Datapoint penalty_saves;
    Datapoint error_free;
    Datapoint conceded;
}

struct WdeDefCoeff {
    Datapoint mockDatapoint;
}

struct CtrDefCoeff {
    Datapoint tackles;
    Datapoint interceptions;
    Datapoint aerial_success;
    Datapoint possessionWon;
    Datapoint dangerZoneContributions;
    Datapoint errors;
    Datapoint conceded;
}

struct DefMidCoeff {
    Datapoint mockDatapoint;
}

struct WdeMidCoeff {
    Datapoint mockDatapoint;
}

struct AttMidCoeff {
    Datapoint mockDatapoint;
}

struct WdeAttCoeff {
    Datapoint mockDatapoint;
}

struct CtrAttCoeff {
    Datapoint closeShots;
    Datapoint conversionRate;
    Datapoint fantasyAssists;
    Datapoint keyPasses;
    Datapoint chancesCreated;
    Datapoint dangerZoneContributions;
    Datapoint bigMiss;
}

// --------------------------------------------
//  Raw
// --------------------------------------------

struct Datapoint {
    uint256 prevTotal;
    uint256 latestTotal;
}