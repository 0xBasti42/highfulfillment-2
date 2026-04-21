// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

/// @title ERC-1271 (replay-safe wrapper)
/// @notice EIP-712 outer hash binds signatures to this contract and chain (Coinbase Smart Wallet pattern).
/// @dev Uses `SmartWalletMessage(bytes32 hash)`; coordinate off-chain signers with any change to this typehash.
abstract contract WalletERC1271 {
    bytes32 private constant _MESSAGE_TYPEHASH = keccak256("SmartWalletMessage(bytes32 hash)");

    function eip712Domain()
        external
        view
        virtual
        returns (
            bytes1 fields,
            string memory name,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        )
    {
        fields = hex"0f";
        (name, version) = _domainNameAndVersion();
        chainId = block.chainid;
        verifyingContract = address(this);
        salt = salt;
        extensions = extensions;
    }

    function isValidSignature(bytes32 hash, bytes calldata signature) public view virtual returns (bytes4 result) {
        if (_isValidSignature({hash: replaySafeHash(hash), signature: signature})) {
            return 0x1626ba7e;
        }

        return 0xffffffff;
    }

    function replaySafeHash(bytes32 hash) public view virtual returns (bytes32) {
        return _eip712Hash(hash);
    }

    function domainSeparator() public view returns (bytes32) {
        (string memory name, string memory version) = _domainNameAndVersion();
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                keccak256(bytes(version)),
                block.chainid,
                address(this)
            )
        );
    }

    function _eip712Hash(bytes32 hash) internal view virtual returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator(), _hashStruct(hash)));
    }

    function _hashStruct(bytes32 hash) internal view virtual returns (bytes32) {
        return keccak256(abi.encode(_MESSAGE_TYPEHASH, hash));
    }

    function _domainNameAndVersion() internal view virtual returns (string memory name, string memory version);

    function _isValidSignature(bytes32 hash, bytes calldata signature) internal view virtual returns (bool);
}
