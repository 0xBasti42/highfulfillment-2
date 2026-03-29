// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IAddressBook {
    function version() external view returns (uint256);
    function get(bytes32 key) external view returns (address);
    function getByName(string calldata name) external view returns (address);
    function keyCount() external view returns (uint256);
    function keyAt(uint256 index) external view returns (bytes32);
    function keys() external view returns (bytes32[] memory);
    function label(bytes32 key) external view returns (string memory);
}
