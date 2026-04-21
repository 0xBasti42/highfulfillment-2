// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

/// @notice Storage layout used by this contract.
/// @custom:storage-location erc7201:coinbase.storage.MultiOwnable
struct MultiOwnableStorage {
    uint256 nextOwnerIndex;
    uint256 removedOwnersCount;
    mapping(uint256 index => bytes owner) ownerAtIndex;
    mapping(bytes bytes_ => bool isOwner_) isOwner;
}

/// @title Multi Ownable
/// @notice Multiple owners as ABI-encoded address (32 bytes) or P-256 public key (64 bytes).
/// @dev Storage slot matches Coinbase Smart Wallet (constant name typo `MUTLI` preserved).
contract MultiOwnable {
    bytes32 private constant MUTLI_OWNABLE_STORAGE_LOCATION =
        0x97e2c6aad4ce5d562ebfaa00db6b9e0fb66ea5d8162ed5b243f51a2e03086f00;

    error Unauthorized();
    error AlreadyOwner(bytes owner);
    error NoOwnerAtIndex(uint256 index);
    error WrongOwnerAtIndex(uint256 index, bytes expectedOwner, bytes actualOwner);
    error InvalidOwnerBytesLength(bytes owner);
    error InvalidEthereumAddressOwner(bytes owner);
    error LastOwner();
    error NotLastOwner(uint256 ownersRemaining);

    event AddOwner(uint256 indexed index, bytes owner);
    event RemoveOwner(uint256 indexed index, bytes owner);

    modifier onlyOwner() virtual {
        _checkOwner();
        _;
    }

    function addOwnerAddress(address owner) external virtual onlyOwner {
        _addOwnerAtIndex(abi.encode(owner), _getMultiOwnableStorage().nextOwnerIndex++);
    }

    function addOwnerPublicKey(bytes32 x, bytes32 y) external virtual onlyOwner {
        _addOwnerAtIndex(abi.encode(x, y), _getMultiOwnableStorage().nextOwnerIndex++);
    }

    function removeOwnerAtIndex(uint256 index, bytes calldata owner) external virtual onlyOwner {
        if (ownerCount() == 1) {
            revert LastOwner();
        }

        _removeOwnerAtIndex(index, owner);
    }

    function removeLastOwner(uint256 index, bytes calldata owner) external virtual onlyOwner {
        uint256 ownersRemaining = ownerCount();
        if (ownersRemaining > 1) {
            revert NotLastOwner(ownersRemaining);
        }

        _removeOwnerAtIndex(index, owner);
    }

    function isOwnerAddress(address account) public view virtual returns (bool) {
        return _getMultiOwnableStorage().isOwner[abi.encode(account)];
    }

    function isOwnerPublicKey(bytes32 x, bytes32 y) public view virtual returns (bool) {
        return _getMultiOwnableStorage().isOwner[abi.encode(x, y)];
    }

    function isOwnerBytes(bytes memory account) public view virtual returns (bool) {
        return _getMultiOwnableStorage().isOwner[account];
    }

    function ownerAtIndex(uint256 index) public view virtual returns (bytes memory) {
        return _getMultiOwnableStorage().ownerAtIndex[index];
    }

    function nextOwnerIndex() public view virtual returns (uint256) {
        return _getMultiOwnableStorage().nextOwnerIndex;
    }

    function ownerCount() public view virtual returns (uint256) {
        MultiOwnableStorage storage $ = _getMultiOwnableStorage();
        return $.nextOwnerIndex - $.removedOwnersCount;
    }

    function removedOwnersCount() public view virtual returns (uint256) {
        return _getMultiOwnableStorage().removedOwnersCount;
    }

    function _initializeOwners(bytes[] memory owners) internal virtual {
        MultiOwnableStorage storage $ = _getMultiOwnableStorage();
        uint256 nextOwnerIndex_ = $.nextOwnerIndex;
        for (uint256 i; i < owners.length; i++) {
            if (owners[i].length != 32 && owners[i].length != 64) {
                revert InvalidOwnerBytesLength(owners[i]);
            }

            if (owners[i].length == 32 && uint256(bytes32(owners[i])) > type(uint160).max) {
                revert InvalidEthereumAddressOwner(owners[i]);
            }

            _addOwnerAtIndex(owners[i], nextOwnerIndex_++);
        }
        $.nextOwnerIndex = nextOwnerIndex_;
    }

    function _addOwnerAtIndex(bytes memory owner, uint256 index) internal virtual {
        if (isOwnerBytes(owner)) revert AlreadyOwner(owner);

        MultiOwnableStorage storage $ = _getMultiOwnableStorage();
        $.isOwner[owner] = true;
        $.ownerAtIndex[index] = owner;

        emit AddOwner(index, owner);
    }

    function _removeOwnerAtIndex(uint256 index, bytes calldata owner) internal virtual {
        bytes memory owner_ = ownerAtIndex(index);
        if (owner_.length == 0) revert NoOwnerAtIndex(index);
        if (keccak256(owner_) != keccak256(owner)) {
            revert WrongOwnerAtIndex({index: index, expectedOwner: owner, actualOwner: owner_});
        }

        MultiOwnableStorage storage $ = _getMultiOwnableStorage();
        delete $.isOwner[owner];
        delete $.ownerAtIndex[index];
        $.removedOwnersCount++;

        emit RemoveOwner(index, owner);
    }

    function _checkOwner() internal view virtual {
        if (isOwnerAddress(msg.sender) || (msg.sender == address(this))) {
            return;
        }

        revert Unauthorized();
    }

    function _getMultiOwnableStorage() internal pure returns (MultiOwnableStorage storage $) {
        assembly ("memory-safe") {
            $.slot := MUTLI_OWNABLE_STORAGE_LOCATION
        }
    }
}
