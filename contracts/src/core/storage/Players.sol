// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { AccessControl } from "@core/AccessControl.sol";
import { Oracle } from "@core/Oracle.sol";
import { RateLimit } from "@core/RateLimit.sol";
import { Player, SeasonMinutes } from "@core/types/PlayerTypes.sol";

/* 
Add multiple storage objects:
- inactive players
- active players

Add multiple scripts:
- Minutes played per player, daily rate limit, version control to check for changes.
- Squads => Eligibility update. Gets called automatically when updating minutes per player.
- Squads => metadata sync. Gets called automatically when updating minutes per player.

Leave space for calling deploy/discontinue, according to result of eligibility scan.
*/

contract Players is AccessControl, RateLimit, Oracle {
    string public getSquads;
    uint256 public playerCount;

    mapping(address tokenAddress => uint256 playerId) public getPlayerId;
    mapping(address tokenAddress => Player player) public getPlayerDataByToken;
    mapping(uint256 playerId => Player player) public getPlayerDataById;

    /// @dev O(1) season lookups per token; kept in sync from `Player.totalMinutes` on add/remove.
    mapping(address tokenAddress => mapping(uint16 seasonStart => uint256 seasonMinutes)) private _seasonMinutesByToken;

    /// @dev Registration order (and removal via swap-and-pop). Used for enumeration only.
    uint256[] private _playerIds;
    /// @dev 1-based index into `_playerIds`; 0 means `playerId` is not currently registered.
    mapping(uint256 playerId => uint256 indexPlusOne) private _playerIdToIndexPlusOne;

    constructor(address addressProvider_) AccessControl(addressProvider_) RateLimit(1 hours) { }

    function scan() external rateLimited {
        // TODO: Implement
    }

    /// @notice Minutes played in the season identified by `seasonStart` (e.g. 2025 for 2025–26).
    function getSeasonMinutes(address tokenAddress, uint16 seasonStart) external view returns (uint256) {
        return _seasonMinutesByToken[tokenAddress][seasonStart];
    }

    /// @notice Number of players returned by `getPlayers` / `getAllPlayers` for the current registry.
    function registeredPlayerCount() external view returns (uint256) {
        return _playerIds.length;
    }

    /// @notice Paginated read — prefer this for large sets if RPC limits are hit.
    function getPlayers(uint256 offset, uint256 limit) external view returns (Player[] memory) {
        return _getPlayersSlice(offset, limit);
    }

    /// @notice Full snapshot (~1000 entries is typically fine for off-chain `eth_call`; use pagination if not).
    function getAllPlayers() external view returns (Player[] memory) {
        return _getPlayersSlice(0, _playerIds.length);
    }

    function _getPlayersSlice(uint256 offset, uint256 limit) private view returns (Player[] memory players) {
        uint256 n = _playerIds.length;
        if (offset >= n || limit == 0) {
            return new Player[](0);
        }
        uint256 end = offset + limit;
        if (end > n) end = n;
        uint256 len = end - offset;
        players = new Player[](len);
        for (uint256 i; i < len; ++i) {
            players[i] = getPlayerDataById[_playerIds[offset + i]];
        }
    }

    function add(Player memory player) external onlyOrchestrator {
        require(player.tokenAddress != address(0), "Players: zero token");
        require(_playerIdToIndexPlusOne[player.playerId] == 0, "Players: duplicate playerId");

        getPlayerDataByToken[player.tokenAddress] = player;
        getPlayerId[player.tokenAddress] = player.playerId;
        getPlayerDataById[player.playerId] = player;

        _applySeasonMinutes(player.tokenAddress, player.totalMinutes);

        _playerIds.push(player.playerId);
        _playerIdToIndexPlusOne[player.playerId] = _playerIds.length;

        playerCount++;
    }

    function remove(Player memory player) external onlyOrchestrator {
        require(_playerIdToIndexPlusOne[player.playerId] != 0, "Players: unknown playerId");

        Player storage stored = getPlayerDataById[player.playerId];
        _clearSeasonMinutes(stored.tokenAddress, stored.totalMinutes);

        delete getPlayerDataByToken[player.tokenAddress];
        delete getPlayerId[player.tokenAddress];
        delete getPlayerDataById[player.playerId];

        _removePlayerId(player.playerId);

        playerCount--;
    }

    function _removePlayerId(uint256 playerId) private {
        uint256 idxPlusOne = _playerIdToIndexPlusOne[playerId];
        uint256 idx = idxPlusOne - 1;
        uint256 lastIdx = _playerIds.length - 1;
        if (idx != lastIdx) {
            uint256 lastId = _playerIds[lastIdx];
            _playerIds[idx] = lastId;
            _playerIdToIndexPlusOne[lastId] = idx + 1;
        }
        _playerIds.pop();
        delete _playerIdToIndexPlusOne[playerId];
    }

    function _applySeasonMinutes(address tokenAddress, SeasonMinutes[] memory totalMinutes) private {
        for (uint256 i; i < totalMinutes.length; ++i) {
            _seasonMinutesByToken[tokenAddress][totalMinutes[i].seasonStart] = totalMinutes[i].seasonMinutes;
        }
    }

    function _clearSeasonMinutes(address tokenAddress, SeasonMinutes[] storage totalMinutes) private {
        for (uint256 i; i < totalMinutes.length; ++i) {
            delete _seasonMinutesByToken[tokenAddress][totalMinutes[i].seasonStart];
        }
    }
}
