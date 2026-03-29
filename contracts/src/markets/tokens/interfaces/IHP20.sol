// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { PoolKey } from "@v4-core/types/PoolKey.sol";

/// @notice Pool lifecycle surface for HP20 (v4 `PoolKey` tracking).
interface IHP20 {
    function ADDRESS_BOOK() external view returns (address);
    function activePoolKey() external view returns (PoolKey memory);
    function isPoolUnlocked() external view returns (bool);

    function lockActivePoolKey(
        PoolKey calldata key
    ) external;
    function unlockPool() external;
    function syncActivePoolKey(
        PoolKey calldata key
    ) external;
}
