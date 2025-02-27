// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.19;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {Migrator} from "src/Migrator.sol";
import {CyberCash} from "src/CyberCash.sol";

contract DeployContracts is Script {
    function setUp() public {}

    address treasury = 0xa0BFD02a7a47CBCA7230E03fbf04A196C3E771E3;

    function run() public returns (address deployedCyberCash, address deployedMigrator) {
        vm.startBroadcast();

        // Configure optimizer settings
        vm.store(address(this), bytes32("optimizer"), bytes32("true"));
        vm.store(address(this), bytes32("optimizerRuns"), bytes32(uint256(1337)));

        Migrator migrator = new Migrator(treasury);
        CyberCash cyberCash = new CyberCash("CyberCash", "CASH", treasury);

        deployedMigrator = address(migrator);
        deployedCyberCash = address(cyberCash);

        vm.stopBroadcast();
    }
}

// forge script script/DeployContracts.s.sol --rpc-url $ARB_MAINNET_URL --private-key $PRIVATE_KEY --broadcast --verify --verifier etherscan --etherscan-api-key $ARBISCAN_API_KEY --optimize --optimizer-runs 1337
