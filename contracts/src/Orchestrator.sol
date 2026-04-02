// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { AddressBook } from "@core/AddressBook.sol";
import { CreateParams, PoolData } from "@core/types/AssetTypes.sol";
import { IInitializer } from "@core/interfaces/IInitializer.sol";

contract Orchestrator is AddressBook {

    // --------------------------------------------
    //  Configuration
    // --------------------------------------------

    mapping(address module => ModuleState state) public getModuleState;

    enum ModuleState {
        NotWhitelisted,
        Initializer,
        PMDeployer,
        VaultDeployer
    }

    // --------------------------------------------
    //  Initialization
    // --------------------------------------------

    constructor(address addressProvider_) AddressBook(addressProvider_) {
        setModuleStates();
    }

    function setModuleStates() internal {
        string[] memory names = new string[](3);
        names[0] = "INITIALIZER";
        names[1] = "PM_DEPLOYER";
        names[2] = "VAULT_DEPLOYER";
        address[] memory addrs = _getAddresses(_addressKeys(names));

        address[] memory modules = new address[](4);
        modules[0] = addrs[0];
        modules[1] = addrs[1];
        modules[2] = addrs[2];

        ModuleState[] memory states = new ModuleState[](4);
        states[0] = ModuleState.Initializer;
        states[1] = ModuleState.PMDeployer;
        states[2] = ModuleState.VaultDeployer;

        _setModuleStates(modules, states);
    }

    // --------------------------------------------
    //  Interface
    // --------------------------------------------

    function deployAsset(CreateParams memory createData) external {
        address initializer_ = _getAddress(_addressKey("INITIALIZER"));
        address pmDeployer_ = _getAddress(_addressKey("PM_DEPLOYER"));
        address vaultDeployer_ = _getAddress(_addressKey("VAULT_DEPLOYER"));

        _validateModuleState(initializer_, ModuleState.Initializer);
        _validateModuleState(pmDeployer_, ModuleState.PMDeployer);
        _validateModuleState(vaultDeployer_, ModuleState.VaultDeployer);

        (address asset, PoolData memory poolData, uint256 excessAsset) = IInitializer(initializer_).deploy(createData);
        
        // ... continue
        //
        // IPMDeployer(pmDeployer_).deploy(asset, poolData);
        // IVaultDeployer(vaultDeployer_).deploy(asset, poolData);
    }

    // --------------------------------------------
    //  Config
    // --------------------------------------------
    
    function _setModuleStates(address[] memory modules, ModuleState[] memory states) internal {
        uint256 length = modules.length;
        if (length != states.length) revert Errors.ArrayLengthsMismatch();
        for (uint256 i; i < length; ++i) {
            getModuleState[modules[i]] = states[i];
        }
    }

    function _validateModuleState(address module, ModuleState state) internal view {
        if (getModuleState[module] != state) {
            revert Errors.WrongModuleState(module, state, getModuleState[module]);
        }
    }
}
