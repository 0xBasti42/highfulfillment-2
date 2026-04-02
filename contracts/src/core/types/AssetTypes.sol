// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import { PoolKey } from "@v4-core/types/PoolKey.sol";

// --------------------------------------------
//  Asset Storage
// --------------------------------------------

struct Asset {
    uint256 assetId;
    address token;
    TokenData tokenData;
    PoolData poolData;
    address positionTracker;
    address lpStore;
    uint256 activatedAt;
    bool hasMigrated;
    address vault;
    address stToken;
	address cToken;
	address vcToken;
    uint256 deactivatedAt;
    bool hasRedistributed;
}

enum Position { Keeper, WdeDef, CtrDef, WdeMid, DefMid, AttMid, WdeFwd, CtrFwd }

struct Club {
    uint256 clubId;
    string name;
    string shorthand;
}

// --------------------------------------------
//  Deployment Parameters
// --------------------------------------------

struct CreateParams {
    TokenData tokenData;
    bytes32 salt;
}

struct TokenData {
    string name;
    string symbol;
    Club club;
    Position position;
}

struct PoolData {
    address numeraire;
    PoolKey activePool;
    address hookDoppler;
    uint256 hookMigrator;
}