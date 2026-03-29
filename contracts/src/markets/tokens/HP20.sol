// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { ERC20 } from "@oz/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@oz/contracts/token/ERC20/extensions/ERC20Permit.sol";

error PoolLocked();
error HP20InvalidAllocation();
error HP20InvalidBeneficiary();
error HP20Unauthorized();
error HP20ZeroController();

address constant PERMIT_2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

/**
 * @title HP20 | HighPotential
 * @author Isla Labs (Tom Jarvis | 0xBasti42)
 * @notice Fixed-supply player ERC20 with pool lock (LBP), immutable controller, and EIP-2612 permit.
 * @custom:experimental DeFi markets covering EPL, NFL, NBA, and more. | Learn more at https://docs.highpotential.io/
 * @custom:security-contact security@islalabs.co
 */
contract HP20 is ERC20Permit {
    address public immutable controller;

    address public pool;
    bool public isPoolUnlocked;

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 initialSupply,
        address recipient,
        address beneficiary,
        uint256 beneficiaryAmount,
        address controller_
    ) ERC20(name_, symbol_) ERC20Permit(name_) {
        if (controller_ == address(0)) revert HP20ZeroController();
        controller = controller_;
        if (beneficiaryAmount > initialSupply) revert HP20InvalidAllocation();
        if (beneficiaryAmount != 0) {
            if (beneficiary == address(0)) revert HP20InvalidBeneficiary();
            _mint(beneficiary, beneficiaryAmount);
        }
        _mint(recipient, initialSupply - beneficiaryAmount);
    }

    modifier onlyController() {
        if (msg.sender != controller) revert HP20Unauthorized();
        _;
    }

    function lockPool(
        address pool_
    ) external onlyController {
        pool = pool_;
        isPoolUnlocked = false;
    }

    function unlockPool() external onlyController {
        isPoolUnlocked = true;
    }

    function burn(
        uint256 amount
    ) external {
        _burn(msg.sender, amount);
    }

    function allowance(
        address owner,
        address spender
    ) public view override returns (uint256) {
        if (spender == PERMIT_2) return type(uint256).max;
        return super.allowance(owner, spender);
    }

    function _update(
        address from,
        address to,
        uint256 value
    ) internal override {
        if (to == pool && !isPoolUnlocked) revert PoolLocked();
        super._update(from, to, value);
    }
}
