// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

/*//////////////////////////////////////////////////////////////
//                        VersionedProxy
//------------------------------------------------------------
//  HighPotential-specific EIP-2535 diamond implementation,
//  designed for trustless, version-controlled upgradeability.
//
//  Where a vanilla diamond lets its owner add, replace, or
//  remove any function at any time, a VersionedProxy admits
//  ONLY additive upgrades, under a strict naming convention
//  (`<family>V<version>(...)`), behind a timelocked authority
//  (VersionedProxyAdmin), with cryptographic provenance on every
//  facet and optional immediate pausing at the routing layer.
//
//  This turns "upgradeable" into "permanently backwards-compatible,
//  with new versions layered on top" — users who pin to a specific
//  selector (e.g. deployV1) can rely on that function remaining
//  callable for the lifetime of the proxy; new versions coexist
//  alongside old ones rather than replacing them.
//
//  Remains compatible with standard diamond tooling (Louper,
//  Etherscan, diamond-ABI mergers) because the IDiamondCut /
//  IDiamondLoupe / IERC165 interfaces are preserved unchanged —
//  only the contract class is renamed to signal the guarantees
//  listed below.
//
//  Modifications vs. the Mudge reference:
//
//  * `DiamondArgs.owner` is replaced by `VersionedProxyArgs.versionedProxyAdmin`.
//    The proxy has no owner; the sole authority over cuts, pause and
//    metadata is a VersionedProxyAdmin contract set once at deployment.
//    The authority check is enforced at the LibDiamond layer, so any
//    future facet that reaches into LibDiamond's privileged mutators
//    cannot bypass it — it is not only the DiamondCutFacet / GovernanceFacet
//    wrappers that hold the line.
//
//  * The fallback consults `selectorPaused` before routing. A paused
//    selector reverts at the proxy layer, regardless of whether the
//    target facet ever implemented a pause modifier.
//
//  * IERC173 is intentionally not registered in supportedInterfaces
//    since the proxy is not owned.
//
//  * The initial cut (run inside the constructor) is restricted to
//    the infrastructure selector whitelist — only DiamondCutFacet,
//    DiamondLoupeFacet (including HP extensions) and GovernanceFacet
//    selectors can be registered at construction. Business facets
//    must be added post-deployment via the VersionedProxyAdmin, where
//    the versioned-naming convention is enforced.
//////////////////////////////////////////////////////////////*/

import { LibDiamond } from "./libraries/LibDiamond.sol";
import { IDiamondCut } from "./interfaces/IDiamondCut.sol";
import { IDiamondLoupe } from "./interfaces/IDiamondLoupe.sol";
import { IDiamondLoupeExt } from "./interfaces/IDiamondLoupeExt.sol";
import { IGovernanceFacet } from "./interfaces/IGovernanceFacet.sol";
import { IERC165 } from "./interfaces/IERC165.sol";

contract VersionedProxy {
    struct VersionedProxyArgs {
        address versionedProxyAdmin;
    }

    constructor(IDiamondCut.FacetCut[] memory _diamondCut, VersionedProxyArgs memory _args) payable {
        // Bootstrap sequence. The ordering matters:
        //   1. Infrastructure whitelist pass (pure check, no state).
        //   2. Initial cut while `versionedProxyAdmin` is still zero — this is
        //      the only moment at which LibDiamond.diamondCut will accept a
        //      caller other than the admin (see
        //      enforceIsVersionedProxyAdminOrUninitialized).
        //   3. Pin the admin. From this SSTORE onwards every privileged
        //      mutator in LibDiamond requires `msg.sender == admin`, so the
        //      constructor is the only path that can write the initial
        //      infrastructure facets.
        //   4. Register ERC-165 interface IDs for loupe discovery.
        //
        // Constructors revert atomically; partial state cannot survive.
        _enforceInfrastructureOnly(_diamondCut);
        LibDiamond.diamondCut(_diamondCut, address(0), new bytes(0));
        LibDiamond.setVersionedProxyAdmin(_args.versionedProxyAdmin);

        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        ds.supportedInterfaces[type(IERC165).interfaceId] = true;
        ds.supportedInterfaces[type(IDiamondCut).interfaceId] = true;
        ds.supportedInterfaces[type(IDiamondLoupe).interfaceId] = true;
        ds.supportedInterfaces[type(IDiamondLoupeExt).interfaceId] = true;
        ds.supportedInterfaces[type(IGovernanceFacet).interfaceId] = true;
        // IERC173 is deliberately omitted: this proxy is owner-less.
    }

    /// @dev Iterates every selector in the initial cut and reverts on the
    ///      first one that is not part of the HighPotential infrastructure
    ///      whitelist. All business-logic selectors must be added later
    ///      through the VersionedProxyAdmin's versioned cut path.
    function _enforceInfrastructureOnly(IDiamondCut.FacetCut[] memory cuts) internal pure {
        uint256 cutsLen = cuts.length;
        for (uint256 i; i < cutsLen; ) {
            bytes4[] memory selectors = cuts[i].functionSelectors;
            uint256 selLen = selectors.length;
            for (uint256 j; j < selLen; ) {
                bytes4 s = selectors[j];
                if (!_isInfrastructureSelector(s)) {
                    revert LibDiamond.NonInfrastructureSelectorInInit(s);
                }
                unchecked { ++j; }
            }
            unchecked { ++i; }
        }
    }

    /// @dev Compile-time-resolved membership test for the infrastructure
    ///      selector set: IDiamondCut + IDiamondLoupe + IERC165 +
    ///      IDiamondLoupeExt + IGovernanceFacet. Uses `.selector` so that
    ///      renaming any interface function at the source level is reflected
    ///      automatically without risk of drift against a hand-maintained
    ///      magic-number table.
    function _isInfrastructureSelector(bytes4 s) internal pure returns (bool) {
        return
            // --- IDiamondCut ---
            s == IDiamondCut.diamondCut.selector
            // --- IDiamondLoupe (standard) ---
            || s == IDiamondLoupe.facets.selector
            || s == IDiamondLoupe.facetFunctionSelectors.selector
            || s == IDiamondLoupe.facetAddresses.selector
            || s == IDiamondLoupe.facetAddress.selector
            // --- IERC165 ---
            || s == IERC165.supportsInterface.selector
            // --- IDiamondLoupeExt (HP extensions) ---
            || s == IDiamondLoupeExt.versionedProxyAdmin.selector
            || s == IDiamondLoupeExt.isFrozen.selector
            || s == IDiamondLoupeExt.facetCodeHash.selector
            || s == IDiamondLoupeExt.selectorPaused.selector
            || s == IDiamondLoupeExt.selectorsPaused.selector
            || s == IDiamondLoupeExt.selectorMeta.selector
            || s == IDiamondLoupeExt.latestInFamily.selector
            // --- IGovernanceFacet ---
            || s == IGovernanceFacet.pauseSelectors.selector
            || s == IGovernanceFacet.unpauseSelectors.selector
            || s == IGovernanceFacet.freeze.selector
            || s == IGovernanceFacet.setSelectorMeta.selector
            || s == IGovernanceFacet.setSelectorMetaBatch.selector
            || s == IGovernanceFacet.setSelectorDeprecated.selector;
    }

    fallback() external payable {
        LibDiamond.DiamondStorage storage ds;
        bytes32 position = LibDiamond.DIAMOND_STORAGE_POSITION;
        assembly { ds.slot := position }

        bytes4 sig = msg.sig;

        if (ds.selectorPaused[sig]) revert LibDiamond.SelectorIsPaused(sig);

        address facet = ds.facetAddressAndSelectorPosition[sig].facetAddress;
        if (facet == address(0)) revert LibDiamond.FunctionNotFound(sig);

        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), facet, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
                case 0 { revert(0, returndatasize()) }
                default { return(0, returndatasize()) }
        }
    }

    receive() external payable {}
}
