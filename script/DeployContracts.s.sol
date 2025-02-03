// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.19;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {Migrator} from "src/Migrator.sol";
import {CyberCash} from "src/CyberCash.sol";

contract DeployContracts is Script {
    function setUp() public {}

    address treasury = 0xAb845D09933f52af5642FC87Dd8FBbf553fd7B33;

    function run() public returns (address deployedCyberCash, address deployedMigrator) {
        vm.startBroadcast();

        // Configure optimizer settings
        vm.store(address(this), bytes32("optimizer"), bytes32("true"));
        vm.store(address(this), bytes32("optimizerRuns"), bytes32(uint256(9999)));

        Migrator migrator = new Migrator(treasury);
        CyberCash cyberCash = new CyberCash("CyberCash", "CASH", treasury);

        deployedMigrator = address(migrator);
        deployedCyberCash = address(cyberCash);

        vm.stopBroadcast();
    }
}

// forge script script/DeployContracts.s.sol --rpc-url $ARB_MAINNET_URL --private-key $PRIVATE_KEY --broadcast --verify --verifier etherscan --etherscan-api-key $ARBISCAN_API_KEY --optimize --optimizer-runs 9999
