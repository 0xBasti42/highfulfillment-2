// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { FCL_Elliptic_ZZ } from "@FreshCryptoLib/FCL_elliptic.sol";

/// @title OwnerValidation
/// @notice Single source of truth for "is this owner payload a controllable owner?". Shared by the wallet
///         (`MultiOwnable`, on add/initialize) and the factory (`getAddress`/`createAccount`, on counterfactual
///         prediction) so that address prediction, deployment, and owner management never diverge.
/// @dev A controllable owner is one that can actually authorize the wallet — i.e. produce a signature or be a
///      `msg.sender`. Inert encodings (`address(0)`, off-curve / zero P-256 keys) are rejected so they can never
///      become the sole owner and permanently brick the account.
library OwnerValidation {
    /// @dev Error signatures intentionally mirror `MultiOwnable`'s so selectors are identical across both.
    error InvalidOwnerBytesLength(bytes owner);
    error InvalidEthereumAddressOwner(bytes owner);
    error InvalidPublicKeyOwner(bytes owner);

    /// @notice Reverts unless `owner` encodes a controllable owner.
    /// @dev 32 bytes: a non-zero EOA address within the uint160 range. 64 bytes: a secp256r1 public key whose
    ///      `(x, y)` lies on the curve (`ecAff_isOnCurve` also rejects `(0, 0)` and out-of-field coordinates).
    function validate(bytes memory owner) internal pure {
        if (owner.length == 32) {
            uint256 value = uint256(bytes32(owner));
            if (value == 0 || value > type(uint160).max) {
                revert InvalidEthereumAddressOwner(owner);
            }
            return;
        }

        if (owner.length == 64) {
            (uint256 x, uint256 y) = abi.decode(owner, (uint256, uint256));
            if (!FCL_Elliptic_ZZ.ecAff_isOnCurve(x, y)) {
                revert InvalidPublicKeyOwner(owner);
            }
            return;
        }

        revert InvalidOwnerBytesLength(owner);
    }
}
