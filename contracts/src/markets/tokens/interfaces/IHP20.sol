// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { PoolKey } from "@v4-core/types/PoolKey.sol";

/// @notice HP20: pool lifecycle + metadata.
interface IHP20 {
    function ADDRESS_BOOK() external view returns (address);
    function tokenURI() external view returns (string memory);
    function metadataHash() external view returns (bytes32);

    function activePoolKey() external view returns (PoolKey memory);
    function isPoolUnlocked() external view returns (bool);

    function setTokenURI(string calldata newURI) external;
    function setMetadataHash(bytes32 newHash) external;

    function lockActivePoolKey(PoolKey calldata key) external;
    function unlockPool() external;
    function syncActivePoolKey(PoolKey calldata key) external;
}
