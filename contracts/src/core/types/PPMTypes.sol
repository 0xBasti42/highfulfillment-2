// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

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
    Datapoint mockDatapoint;
}

struct WdeDefCoeff {
    Datapoint mockDatapoint;
}

struct CtrDefCoeff {
    Datapoint mockDatapoint;
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
    Datapoint mockDatapoint;
}

// --------------------------------------------
//  Raw
// --------------------------------------------

struct Datapoint {
    string id;
    uint256 prevTotal;
    uint256 latestTotal;
}