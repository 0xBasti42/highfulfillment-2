// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { AccessControl } from "@core/AccessControl.sol";
import { Fixture } from "@core/types/FixtureTypes.sol";

contract Fixtures is AccessControl {
    uint256 public fixtureCount;

    mapping(string fixtureName => Fixture fixture) public getFixture;
    mapping(string fixtureName => uint256 fixtureId) public getFixtureId;

    constructor(address addressProvider_) AccessControl(addressProvider_) { }

    function add(Fixture memory fixture) external onlyOrchestrator {
        getFixture[fixture.fixtureName] = fixture;
        getFixtureId[fixture.fixtureName] = fixture.fixtureId;
        fixtureCount++;
    }

    function remove(Fixture memory fixture) external onlyOrchestrator {
        delete getFixture[fixture.fixtureName];
        delete getFixtureId[fixture.fixtureName];
        fixtureCount--;
    }
}
