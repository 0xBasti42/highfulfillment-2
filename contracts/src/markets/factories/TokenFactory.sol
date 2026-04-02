// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import { ITokenFactory } from "@markets/factories/interfaces/ITokenFactory.sol";
import { AddressBook } from "@base/AddressBook.sol";
import { HP20 } from "@markets/tokens/HP20.sol";
import { CreateParams } from "@markets/types/Types.sol";
import { Errors } from "@markets/libraries/Errors.sol";

contract TokenFactory is ITokenFactory, AddressBook {
    constructor(address addressProvider_) AddressBook(addressProvider_) { }

    modifier onlyInitializer() {
        if (msg.sender != getAddress(_addressKey("INITIALIZER"))) revert Errors.Unauthorized();
        _;
    }

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
