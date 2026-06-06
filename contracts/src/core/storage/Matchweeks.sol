// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { AccessControl } from "@core/AccessControl.sol";
import { Errors } from "@core/libraries/EventsAndErrors.sol";
import { Oracle } from "@core/Oracle.sol";
import { RateLimit } from "@core/RateLimit.sol";
import { Matchweek, Status } from "@core/types/FixtureTypes.sol";

contract Matchweeks is AccessControl, RateLimit, Oracle {
    uint16 public currentSeason;

    uint8 public liveMatchweek;
    uint8 public tradingMatchweek;

    /// @notice Returns the Matchweek struct for a given season and matchweek.
    mapping(uint16 seasonStartYear => mapping(uint8 matchweekNumber => Matchweek matchweek)) public getMatchweek;

    /// @notice Returns the script for scan() functions.
    mapping(uint256 version => string script) public getMatchweeksScript;

    /// @notice The latest script version.
    uint256 public latestScriptVersion;

    /// @notice Emitted when the script is updated.
    event MatchweeksScriptUpdated(uint256 indexed version, string script);

    // --------------------------------------------
    //  Initialization
    // --------------------------------------------

    constructor(address addressProvider_, string memory matchweeksScript_)
        AccessControl(addressProvider_)
        RateLimit(24 hours)
    {
        getMatchweeksScript[0] = matchweeksScript_;
        emit MatchweeksScriptUpdated(0, matchweeksScript_);

        uint16 seasonStartYear = 2026;
        currentSeason = seasonStartYear;
        liveMatchweek = 1;
        tradingMatchweek = 1;

        uint8 totalMatchweeks = 38;

        for (uint8 n = 1; n <= totalMatchweeks; ++n) {
            getMatchweek[seasonStartYear][n] = Matchweek({
                seasonStartYear: seasonStartYear,
                matchweekNumber: n,
                status: Status.Pending,
                startTime: block.timestamp + 1 years,
                endTime: block.timestamp + 1 years + 2 days
            });
        }
    }

    function setMatchweeksScript(string memory matchweeksScript_) external onlyOrchestrator {
        uint256 newVersion = latestScriptVersion + 1;
        getMatchweeksScript[newVersion] = matchweeksScript_;
        latestScriptVersion = newVersion;
        emit MatchweeksScriptUpdated(newVersion, matchweeksScript_);
    }

    // --------------------------------------------
    //  Storage
    // --------------------------------------------

    function newSeason() external rateLimited {
        uint256 endTime = getMatchweek[currentSeason][38].endTime;
        if (endTime >= block.timestamp) revert Errors.CurrentSeasonNotEnded(endTime);

        uint16 seasonStartYear = currentSeason + 1;
        currentSeason = seasonStartYear;
        liveMatchweek = 1;
        tradingMatchweek = 1;

        uint8 totalMatchweeks = 38;

        for (uint8 n = 1; n <= totalMatchweeks; ++n) {
            getMatchweek[seasonStartYear][n] = Matchweek({
                seasonStartYear: seasonStartYear,
                matchweekNumber: n,
                status: Status.Pending,
                startTime: block.timestamp + n * 7 days,
                endTime: block.timestamp + n * 7 days + 2 days
            });
        }
    }

    function _editTimes(uint8 number, uint64 startTime, uint64 endTime) internal {
        Matchweek storage m = getMatchweek[currentSeason][number];
        if (m.matchweekNumber == 0) return;
        m.startTime = startTime;
        m.endTime = endTime;
    }

    // --------------------------------------------
    //  Refresh
    // --------------------------------------------

    function scan() external rateLimited {
        _sendRequestInlineJS(getMatchweeksScript[latestScriptVersion]);
    }

    function _fulfillRequest(bytes32 /* requestId */, bytes memory response, bytes memory err)
        internal
        override
    {
        if (err.length != 0 || response.length == 0) return;
        uint256 entryCount = response.length / 17;
        for (uint256 i; i < entryCount; ++i) {
            uint256 base = i * 17;
            uint8 number = uint8(response[base]);
            uint64 startTime = _readUint64(response, base + 1);
            uint64 endTime = _readUint64(response, base + 9);
            _editTimes(number, startTime, endTime);
        }

        // liveMatchweek = filter(matchweek.endTime >= block.timestamp).sort(Matchweek.startTime) => matchweekNumber
        // tradingMatchweek = filter(matchweek.endTime >= block.timestamp).sort(Matchweek.startTime) => matchweekNumber or matchweekNumber + 1
    }

    function _readUint64(bytes memory data, uint256 offset) private pure returns (uint64 value) {
        assembly {
            value := shr(192, mload(add(add(data, 0x20), offset)))
        }
    }

    // --------------------------------------------
    //  Views
    // --------------------------------------------

    function getMatchweeksForSeason(uint16 seasonStartYear) external view returns (Matchweek[] memory matchweeks) {
        uint8 totalMatchweeks = 38;
        matchweeks = new Matchweek[](totalMatchweeks);
        for (uint8 n = 1; n <= totalMatchweeks; ++n) {
            matchweeks[n - 1] = getMatchweek[seasonStartYear][n];
        }
    }
}