// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import { ITokenFactory } from "@markets/factories/interfaces/ITokenFactory.sol";
import { ImmutableAddressProvider } from "@base/ImmutableAddressProvider.sol";
import { HP20 } from "@markets/tokens/HP20.sol";
import { CreateParams } from "@markets/types/Types.sol";

error Unauthorized();

/// @custom:security-contact security@whetstone.cc
contract TokenFactory is ITokenFactory, ImmutableAddressProvider {
    constructor(address addressProvider_) ImmutableAddressProvider(addressProvider_) { }

    modifier onlyInitializer() {
        if (msg.sender != getAddress(_addressKey("INITIALIZER"))) revert Unauthorized();
        _;
    }

    /**
     * @notice Creates a new HP20 token
     * @param salt Salt used for the create2 deployment
     * @param data Creation parameters encoded as bytes
     * @param addressProvider_ Address provider
     */
    function create(
        uint256 totalSupply,
        CreateParams calldata createData
    ) external onlyInitializer returns (address asset, bytes32 salt) {
        ( string memory name, string memory symbol, string memory tokenURI, bytes32 metadataHash, bytes32 salt) = abi.decode(
            createData, (string, string, string, bytes32, bytes32)
        );

        address asset = address(
            new HP20{ salt: salt }(
                name,
                symbol,
                tokenURI,
                metadataHash,
                totalSupply,
                msg.sender,
                address(addressProvider)
            )
        );

        return (asset, salt);
    }
}
