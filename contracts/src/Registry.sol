// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { PoolKey } from "@v4-core/types/PoolKey.sol";

// Can sum different weights, and take an average across them as the final value. This should increase accuracy.
enum PositionTime { Keeper, WdeDef, CtrlDef, WdeMid, DefMid, AttMid, WideFwd, CtrlFwd }

// Kpr takes Kpr, CtrDef, CtrMid, CtrFwd (2:1:1:1). CtrDef takes CtrDef, DefMid, WdeDef (2:2:1).
// WdeDef takes WdeDef, WdeMid, CtrlDef (2:2:1). DefMid takes DefMid, AttMid, CtrDef (2:2:1).
// WdeMid takes WdeMid, AttMid, WdeFwd (2:2:1). AttMid takes AttMid, WideMid, CtrFwd (2:2:1).
// WideFwd takes WdeFwd, CtrFwd, WdeMid (2:2:1). CtrFwd takes CtrFwd, AttMid, WdeFwd (2:2:1).
enum Position { Keeper, WdeDef, CtrDef, WdeMid, DefMid, AttMid, WdeFwd, CtrFwd }

// PositionTime tracks minutes spent in each position. This can be added to PPM and collected in real time.
// AvgPosition extracts most common position from PositionTime, which is stored in PlayerVault alongside PPM.

struct VaultSet {
	address tokenAddress;
	Position position;
	address vaultAddress;
	address stTokenAddress;
	address cTokenCollection;
	address vcTokenCollection;
	bool isActive;
	bool isUtilized;
}

struct TokenSet {
    address token;
    address vault;
    address dopplerHook;
    address migratorHook;
    address nftStorage;
    bool hasMigrated;
    bool isActive;
    uint256 deactivatedAt; // for +90d remigration
    bool sunsetComplete;
}

struct Asset {
    address token;
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

// --------------------------------------------
//  PlayerVault PPM storage
// --------------------------------------------

// Each Datapoint only takes the proprietary combination of rawStats. Full data insights available at x402 endpoint.
struct Datapoint {
    string id;
    uint256 prevTotal;
    uint256 latestTotal;
}

struct GkCoeff {
    Datapoint gkDistribution;
    Datapoint gkSaves;
    Datapoint gkClaims;
    Datapoint gkProgression;
    Datapoint gkErrorFree;
    uint256 prevTotal;
    uint256 latestTotal;
}

// prevTotal/latestTotal enables easy lookup for latest matchweek values, which are canonical and pre-calculated by mwEndTime.
// -- Calling PlayerVault.claim() or RewardsTreasury.distribute() after mwEndTime collects all mwPoints values from each PlayerVault
//    and the vault's utilization rate (skips 0% utilized). Sum of all totals is M_adj for PBR.

// ...

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

// Keep running totals onchain, granular by-the-matchweek storage offchain via x402.

struct PPM {
    address token;
    address vault;
    AvgPosition avgPosition;
    Coefficients coefficients;
    uint256 prevTotal;
    uint256 latestTotal;
}

// PlayerVault.PPM.positionTime()   // updated via StatsPerform (1-11) position data in realtime. ++1 for every 60s that an Asset spends in positions 1-11.
// PlayerVault.matchweekPoints()    // returns matchweekPoints as (PPM.latestTotal - PPM.prevTotal)
// PlayerVault.totalPoints()        // returns PPM.latestTotal

contract Registry { }
