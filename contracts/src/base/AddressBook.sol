// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/// @notice Minimal read surface for integrations that only need lookups and enumeration.
interface IAddressProvider {
    function version() external view returns (uint256);
    function get(
        bytes32 key
    ) external view returns (address);
    function getByName(
        string calldata name
    ) external view returns (address);
    function keyCount() external view returns (uint256);
    function keyAt(
        uint256 index
    ) external view returns (bytes32);
    function keys() external view returns (bytes32[] memory);
    function label(
        bytes32 key
    ) external view returns (string memory);
}

/// @title HighPotential Address Provider
/// @notice Dynamic registry: each logical slot is a `bytes32` key; string names use `keccak256(bytes(name))`.
/// @dev Enumeration tracks keys with a non-zero address. Mutations are role-gated; `version` increments per mutation.
contract AddressBook is AccessControl {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    bytes32 public constant ADDRESS_MANAGER_ROLE = keccak256("ADDRESS_MANAGER_ROLE");

    uint256 public version;

    EnumerableSet.Bytes32Set private _keys;
    mapping(bytes32 key => address) private _addr;
    mapping(bytes32 key => string) private _label;

    event AddressSet(uint256 indexed version, bytes32 indexed key, string name, address previous, address current);

    error ZeroDefaultAdmin();
    error ZeroKey();
    error EmptyName();
    error NameKeyMismatch();
    error AddressAlreadyBound(bytes32 key, address current);

    constructor(
        address defaultAdmin
    ) {
        if (defaultAdmin == address(0)) revert ZeroDefaultAdmin();
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(ADDRESS_MANAGER_ROLE, defaultAdmin);
        version = 1;
    }

    /// @notice Upsert by human-readable `name`. Storage key is `keccak256(bytes(name))`.
    function setName(
        string calldata name,
        address addr
    ) external onlyRole(ADDRESS_MANAGER_ROLE) {
        if (bytes(name).length == 0) revert EmptyName();
        bytes32 key = keccak256(bytes(name));
        _set(key, addr, name);
    }

    /// @notice Upsert by raw key. Non-empty `name` must satisfy `keccak256(bytes(name)) == key`; use "" to keep the existing label.
    function setKey(
        bytes32 key,
        address addr,
        string calldata name
    ) external onlyRole(ADDRESS_MANAGER_ROLE) {
        if (key == bytes32(0)) revert ZeroKey();
        if (bytes(name).length != 0) {
            if (keccak256(bytes(name)) != key) revert NameKeyMismatch();
        }
        string memory label_ = name;
        if (bytes(name).length == 0) {
            label_ = _label[key];
        }
        _set(key, addr, label_);
    }

    /// @notice First-write only: reverts if `key` already holds a non-zero address.
    function registerName(
        string calldata name,
        address addr
    ) external onlyRole(ADDRESS_MANAGER_ROLE) {
        if (bytes(name).length == 0) revert EmptyName();
        if (addr == address(0)) return;
        bytes32 key = keccak256(bytes(name));
        address cur = _addr[key];
        if (cur != address(0)) revert AddressAlreadyBound(key, cur);
        _set(key, addr, name);
    }

    /// @notice First-write only for raw keys.
    function registerKey(
        bytes32 key,
        address addr,
        string calldata name
    ) external onlyRole(ADDRESS_MANAGER_ROLE) {
        if (key == bytes32(0)) revert ZeroKey();
        if (addr == address(0)) return;
        if (bytes(name).length != 0 && keccak256(bytes(name)) != key) revert NameKeyMismatch();
        address cur = _addr[key];
        if (cur != address(0)) revert AddressAlreadyBound(key, cur);
        string memory label_ = name;
        if (bytes(name).length == 0) {
            label_ = _label[key];
        }
        _set(key, addr, label_);
    }

    function get(
        bytes32 key
    ) external view returns (address) {
        return _addr[key];
    }

    function getByName(
        string calldata name
    ) external view returns (address) {
        return _addr[keccak256(bytes(name))];
    }

    function label(
        bytes32 key
    ) external view returns (string memory) {
        return _label[key];
    }

    function keyCount() external view returns (uint256) {
        return _keys.length();
    }

    function keyAt(
        uint256 index
    ) external view returns (bytes32) {
        return _keys.at(index);
    }

    function keys() external view returns (bytes32[] memory) {
        return _keys.values();
    }

    function _set(
        bytes32 key,
        address addr,
        string memory name
    ) private {
        address prev = _addr[key];
        if (addr == address(0)) {
            if (prev == address(0)) return;
            _addr[key] = address(0);
            _keys.remove(key);
            delete _label[key];
            unchecked {
                version += 1;
            }
            emit AddressSet(version, key, name, prev, address(0));
            return;
        }

        if (prev == address(0)) {
            _keys.add(key);
        }

        _addr[key] = addr;
        if (bytes(name).length != 0) {
            _label[key] = name;
        }

        unchecked {
            version += 1;
        }
        emit AddressSet(version, key, name, prev, addr);
    }
}
