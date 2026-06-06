// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

/*//////////////////////////////////////////////////////////////
//                        LibDiamond
//------------------------------------------------------------
//  Shared storage + cut machinery for the VersionedProxy family.
//
//  Architectural intent
//  --------------------
//  VersionedProxy is built for trustless, version-controlled
//  upgradeability: new function versions are layered on top of
//  old ones rather than replacing them, users can pin to a
//  specific selector for the lifetime of the proxy, and every
//  state transition is cryptographically scoped so governance
//  cannot retroactively rewrite history. This library is where
//  those invariants live on-chain — they are enforced here at the
//  storage-access layer, not only at the outer governance surface
//  (VersionedProxyAdmin), so they hold even if the outer surface
//  is ever replaced or bypassed.
//
//  Relation to the EIP-2535 reference
//  ----------------------------------
//  Based on Nick Mudge's diamond-1 reference implementation
//  (<https://github.com/mudgen/diamond-1-hardhat>) with the
//  following HighPotential-specific modifications:
//
//  1. Append-only cuts: `Replace` and `Remove` actions are rejected
//     at the library level. Only `Add` is supported. This makes
//     "no function ever registered on this proxy can be silently
//     replaced or removed" an on-chain invariant rather than a
//     governance policy.
//
//  2. VersionedProxyAdmin authority: replaces the `contractOwner`
//     field. Cuts, pause, and metadata changes are gated on a
//     single authority that is set once at deployment (via
//     `setVersionedProxyAdmin`) and subsequently immutable.
//     The authority check lives *inside* this library — every
//     privileged mutator (diamondCut, freezeDiamond,
//     setSelectorPaused, setSelectorMeta, setSelectorDeprecated)
//     begins with enforceIsVersionedProxyAdmin, so a future facet
//     that inadvertently exposes one of these library entry points
//     cannot silently become a privilege-escalation gateway. The
//     facet-level wrappers keep the same call as an auditor-facing
//     declaration of intent (defence in depth).
//
//  3. Selector pause: per-selector boolean flag consulted by the
//     proxy's fallback. Pausing is retroactive (works for any
//     registered selector regardless of facet opt-in) and does
//     not modify the selector routing itself — paused selectors
//     stay on file and can be reactivated, they simply revert at
//     the proxy layer while the pause is in effect.
//
//  4. Facet code-hash provenance: `extcodehash` of each facet is
//     recorded at Add time and re-checked on subsequent Adds for
//     the same address, preventing facet-address reuse with
//     altered code.
//
//  5. One-shot init contracts: each `_init` address can be used
//     at most once across the proxy's lifetime, preventing
//     replayed initialisation.
//
//  6. Freeze switch: one-way flag that permanently disables cuts,
//     converting the proxy into an immutable contract system when
//     governance decides no further upgrades are required.
//
//  7. Selector metadata: first-class on-chain records of
//     `(family, version, registeredAt, deprecated)` per selector,
//     with monotonicity enforcement (`version == latestInFamily
//     + 1`, first in family == 1, set-at-most-once). Lets
//     version-aware clients walk the family chain without any
//     ABI-name parsing and gives the proxy a cryptographic link
//     between an EIP-2535 selector and its human-readable version.
//////////////////////////////////////////////////////////////*/

import { IDiamondCut } from "../interfaces/IDiamondCut.sol";

library LibDiamond {
    // --------------------------------------------
    //  Storage
    // --------------------------------------------

    bytes32 constant DIAMOND_STORAGE_POSITION = keccak256("diamond.standard.diamond.storage");

    struct FacetAddressAndSelectorPosition {
        address facetAddress;
        uint16 selectorPosition;
    }

    struct SelectorMeta {
        bytes32 family;        // groups versioned selectors, e.g. keccak256("deploy")
        uint32 version;        // 1, 2, 3, … monotonically increasing per family
        uint64 registeredAt;   // block.timestamp when metadata was set
        bool deprecated;       // governance-set hint: clients should migrate
    }

    struct DiamondStorage {
        // --- EIP-2535 core routing ---
        mapping(bytes4 selector => FacetAddressAndSelectorPosition) facetAddressAndSelectorPosition;
        bytes4[] selectors;
        mapping(bytes4 interfaceId => bool) supportedInterfaces;

        // --- HighPotential governance ---
        address versionedProxyAdmin;                                 // sole authority for cuts, pause, metadata
        bool frozen;                                           // one-way: no more cuts once true
        mapping(address facet => bytes32) facetCodeHash;       // provenance pin per facet address
        mapping(bytes4 selector => bool) selectorPaused;       // per-selector routing kill-switch
        mapping(address init => bool) usedInit;                // init contracts are single-shot
        mapping(bytes4 selector => SelectorMeta) selectorMeta; // optional version metadata
        mapping(bytes32 family => bytes4) latestInFamily;      // family → current recommended selector
    }

    function diamondStorage() internal pure returns (DiamondStorage storage ds) {
        bytes32 position = DIAMOND_STORAGE_POSITION;
        assembly { ds.slot := position }
    }

    // --------------------------------------------
    //  Events
    // --------------------------------------------

    event DiamondCut(IDiamondCut.FacetCut[] _diamondCut, address _init, bytes _calldata);
    event VersionedProxyAdminSet(address indexed timelock);
    event DiamondFrozen(uint256 timestamp);
    event SelectorPausedSet(bytes4 indexed selector, bool paused);
    event FacetCodeHashRecorded(address indexed facet, bytes32 codeHash);
    event SelectorMetaSet(bytes4 indexed selector, bytes32 indexed family, uint32 version);
    event SelectorDeprecationSet(bytes4 indexed selector, bool deprecated);

    // --------------------------------------------
    //  Errors
    // --------------------------------------------

    error NotVersionedProxyAdmin(address caller);
    error VersionedProxyAdminAlreadySet();
    error ZeroVersionedProxyAdmin();

    error AppendOnly(IDiamondCut.FacetCutAction action);
    error NoSelectors();
    error ZeroFacetAddress();
    error SelectorAlreadyRegistered(bytes4 selector, address existingFacet);
    error SelectorNotRegistered(bytes4 selector);
    error NotContract(address target);
    error FacetCodeHashDrift(address facet, bytes32 stored, bytes32 actual);

    error DiamondIsFrozen();

    error InitAlreadyUsed(address init);
    error InitFailedWithoutReason();
    error CalldataWithoutInit();
    error InitWithoutCalldata();

    error FunctionNotFound(bytes4 selector);
    error SelectorIsPaused(bytes4 selector);

    error MetaAlreadySet(bytes4 selector);
    error FirstVersionMustBeOne(bytes32 family, uint32 got);
    error VersionNotMonotonic(bytes32 family, uint32 got, uint32 expected);
    error NonInfrastructureSelectorInInit(bytes4 selector);

    // --------------------------------------------
    //  VersionedProxyAdmin authority
    // --------------------------------------------

    function setVersionedProxyAdmin(address _timelock) internal {
        DiamondStorage storage ds = diamondStorage();
        if (ds.versionedProxyAdmin != address(0)) revert VersionedProxyAdminAlreadySet();
        if (_timelock == address(0)) revert ZeroVersionedProxyAdmin();
        ds.versionedProxyAdmin = _timelock;
        emit VersionedProxyAdminSet(_timelock);
    }

    function versionedProxyAdmin() internal view returns (address) {
        return diamondStorage().versionedProxyAdmin;
    }

    function enforceIsVersionedProxyAdmin() internal view {
        if (msg.sender != diamondStorage().versionedProxyAdmin) {
            revert NotVersionedProxyAdmin(msg.sender);
        }
    }

    /// @dev Variant used by `diamondCut` only: passes if either the caller is
    ///      the admin, or if the admin has not yet been set. The latter case
    ///      covers the one-shot bootstrap cut executed inside the
    ///      VersionedProxy constructor, which runs before the admin address
    ///      is installed. Once `setVersionedProxyAdmin` has pinned a non-zero
    ///      admin, this helper behaves identically to
    ///      `enforceIsVersionedProxyAdmin` — so post-construction there is no
    ///      window in which cuts can be attempted by anyone else.
    function enforceIsVersionedProxyAdminOrUninitialized() internal view {
        address admin = diamondStorage().versionedProxyAdmin;
        if (admin == address(0)) return;
        if (msg.sender != admin) revert NotVersionedProxyAdmin(msg.sender);
    }

    // --------------------------------------------
    //  Freeze
    // --------------------------------------------

    function enforceNotFrozen() internal view {
        if (diamondStorage().frozen) revert DiamondIsFrozen();
    }

    function freezeDiamond() internal {
        enforceIsVersionedProxyAdmin();
        DiamondStorage storage ds = diamondStorage();
        ds.frozen = true;
        emit DiamondFrozen(block.timestamp);
    }

    function isFrozen() internal view returns (bool) {
        return diamondStorage().frozen;
    }

    // --------------------------------------------
    //  Cut (append-only)
    // --------------------------------------------

    function diamondCut(
        IDiamondCut.FacetCut[] memory _diamondCut,
        address _init,
        bytes memory _calldata
    ) internal {
        enforceIsVersionedProxyAdminOrUninitialized();
        enforceNotFrozen();

        uint256 len = _diamondCut.length;
        for (uint256 i; i < len; ) {
            IDiamondCut.FacetCutAction action = _diamondCut[i].action;
            if (action != IDiamondCut.FacetCutAction.Add) revert AppendOnly(action);

            _addFunctions(_diamondCut[i].facetAddress, _diamondCut[i].functionSelectors);

            unchecked { ++i; }
        }

        emit DiamondCut(_diamondCut, _init, _calldata);
        _initializeDiamondCut(_init, _calldata);
    }

    function _addFunctions(address _facetAddress, bytes4[] memory _functionSelectors) private {
        uint256 selLen = _functionSelectors.length;
        if (selLen == 0) revert NoSelectors();
        if (_facetAddress == address(0)) revert ZeroFacetAddress();
        enforceHasContractCode(_facetAddress);

        DiamondStorage storage ds = diamondStorage();

        // Code-hash provenance: pin the facet's extcodehash the first time we see
        // it, and on every subsequent Add using the same address require the
        // code hash to match. This protects against re-registering an address
        // whose code has been swapped via SELFDESTRUCT+CREATE2 tricks (largely
        // neutralised post-Cancun, but cheap defence in depth).
        bytes32 codeHash;
        assembly { codeHash := extcodehash(_facetAddress) }

        bytes32 storedHash = ds.facetCodeHash[_facetAddress];
        if (storedHash == bytes32(0)) {
            ds.facetCodeHash[_facetAddress] = codeHash;
            emit FacetCodeHashRecorded(_facetAddress, codeHash);
        } else if (storedHash != codeHash) {
            revert FacetCodeHashDrift(_facetAddress, storedHash, codeHash);
        }

        uint16 selectorCount = uint16(ds.selectors.length);
        for (uint256 j; j < selLen; ) {
            bytes4 selector = _functionSelectors[j];
            address existingFacet = ds.facetAddressAndSelectorPosition[selector].facetAddress;
            if (existingFacet != address(0)) {
                revert SelectorAlreadyRegistered(selector, existingFacet);
            }
            ds.facetAddressAndSelectorPosition[selector] = FacetAddressAndSelectorPosition({
                facetAddress: _facetAddress,
                selectorPosition: selectorCount
            });
            ds.selectors.push(selector);
            unchecked {
                ++selectorCount;
                ++j;
            }
        }
    }

    function _initializeDiamondCut(address _init, bytes memory _calldata) private {
        if (_init == address(0)) {
            if (_calldata.length != 0) revert CalldataWithoutInit();
            return;
        }
        if (_calldata.length == 0) revert InitWithoutCalldata();
        enforceHasContractCode(_init);

        DiamondStorage storage ds = diamondStorage();
        if (ds.usedInit[_init]) revert InitAlreadyUsed(_init);
        ds.usedInit[_init] = true;

        (bool success, bytes memory err) = _init.delegatecall(_calldata);
        if (!success) {
            if (err.length > 0) {
                // Bubble the revert data verbatim so the caller sees the original error.
                assembly {
                    let size := mload(err)
                    revert(add(err, 0x20), size)
                }
            }
            revert InitFailedWithoutReason();
        }
    }

    // --------------------------------------------
    //  Selector pause
    // --------------------------------------------

    function setSelectorPaused(bytes4 selector, bool paused) internal {
        enforceIsVersionedProxyAdmin();
        DiamondStorage storage ds = diamondStorage();
        if (ds.facetAddressAndSelectorPosition[selector].facetAddress == address(0)) {
            revert SelectorNotRegistered(selector);
        }
        ds.selectorPaused[selector] = paused;
        emit SelectorPausedSet(selector, paused);
    }

    // --------------------------------------------
    //  Selector metadata
    // --------------------------------------------

    /// @dev Registers metadata for an already-added selector. Enforces two
    ///      invariants that together guarantee a monotonically-versioned
    ///      family chain:
    ///        1. Each selector's metadata is set at most once (registration
    ///           is not revisable).
    ///        2. Versions within a family strictly equal `previous + 1`, with
    ///           the first version in a family being `1`.
    ///      Both checks are defence in depth. VersionedProxyAdmin pre-validates the
    ///      same invariants against the loupe before the timelock window
    ///      starts; this library-level enforcement guarantees the invariant
    ///      holds even if the timelock is bypassed in future.
    function setSelectorMeta(
        bytes4 selector,
        bytes32 family,
        uint32 version
    ) internal {
        enforceIsVersionedProxyAdmin();
        DiamondStorage storage ds = diamondStorage();

        if (ds.facetAddressAndSelectorPosition[selector].facetAddress == address(0)) {
            revert SelectorNotRegistered(selector);
        }
        if (ds.selectorMeta[selector].version != 0) {
            revert MetaAlreadySet(selector);
        }

        bytes4 latestSelector = ds.latestInFamily[family];
        if (latestSelector == bytes4(0)) {
            if (version != 1) revert FirstVersionMustBeOne(family, version);
        } else {
            uint32 expected = ds.selectorMeta[latestSelector].version + 1;
            if (version != expected) {
                revert VersionNotMonotonic(family, version, expected);
            }
        }

        ds.selectorMeta[selector] = SelectorMeta({
            family: family,
            version: version,
            registeredAt: uint64(block.timestamp),
            deprecated: false
        });
        ds.latestInFamily[family] = selector;
        emit SelectorMetaSet(selector, family, version);
    }

    function setSelectorDeprecated(bytes4 selector, bool deprecated) internal {
        enforceIsVersionedProxyAdmin();
        DiamondStorage storage ds = diamondStorage();
        if (ds.facetAddressAndSelectorPosition[selector].facetAddress == address(0)) {
            revert SelectorNotRegistered(selector);
        }
        ds.selectorMeta[selector].deprecated = deprecated;
        emit SelectorDeprecationSet(selector, deprecated);
    }

    // --------------------------------------------
    //  Utilities
    // --------------------------------------------

    function enforceHasContractCode(address _contract) internal view {
        uint256 size;
        assembly { size := extcodesize(_contract) }
        if (size == 0) revert NotContract(_contract);
    }
}
