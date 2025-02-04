// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CyberCash} from "src/CyberCash.sol";
import {Migrator} from "src/Migrator.sol";

// ============================================
// ==              CUSTOM ERRORS             ==
// ============================================
error NotInitialized();
error ZeroAmount();
error ZeroAddress();

contract SelfTransferTest is Test {
    // addresses
    address payable Alice = payable(0x46340b20830761efd32832A74d7169B29FEB9758);
    address payable Bob = payable(0x490b1E689Ca23be864e55B46bf038e007b528208);
    address payable liquidityPool = payable(0x3A30aaf1189E830b02416fb8C513373C659ed748); // fake LP
    address payable treasury = payable(0xAb845D09933f52af5642FC87Dd8FBbf553fd7B33);
    address psm = 0x17A8541B82BF67e10B0874284b4Ae66858cb1fd5;

    // CyberCash instance
    CyberCash cyberCash;

    // Migrator instance
    Migrator migrator;

    // time
    uint256 oneYear = 60 * 60 * 24 * 365;

    // Constants
    uint256 constant INITIAL_SUPPLY = 1e28; // 10 billion
    uint256 constant INITIAL_TOTAL_BURN = 1;
    uint256 constant RESERVE_START = 1e27; // 1 billion
    uint256 constant RESERVE_BUFFER = 1e9; // Token reserve in the LP that cannot be burned
    uint256 constant MINT_PER_SECOND = 31709791983764586504; // 1 bn tokens p.a. (365 days)
    uint256 constant BURN_ON_TRANSFER = 5; // 0.5%
    uint256 constant BURN_FROM_LP = 2; // 0.2%
    uint256 constant BURN_PRECISION = 1000;
    uint256 constant REWARD_PRECISION = 1e18;
    uint256 constant ONE_TOKEN = 1e18;
    uint256 constant PSM_DECIMALS = 18;
    uint256 constant PSM_RATIO = 1e18;

    //////////////////////////////////////
    /////// SETUP
    //////////////////////////////////////
    function setUp() public {
        // Create main net fork
        vm.createSelectFork({urlOrAlias: "alchemy_arbitrum_api", blockNumber: 260000000});

        // Create contract instances
        migrator = new Migrator(treasury);
        cyberCash = new CyberCash("CyberCash", "CASH", treasury);
    }

    //////////////////////////////////////
    /////// HELPER FUNCTIONS
    //////////////////////////////////////

    // register the liquidity pool & migrator in the token contract
    function helper_initialize() public {
        vm.prank(treasury);
        cyberCash.initialize(liquidityPool, address(migrator));
    }

    //////////////////////////////////////
    /////// TESTS - CyberCash
    //////////////////////////////////////
    function testSuccess_SelfTransferIncreaseBurnScore() public {
        // Scenario 1: Transfer CASH to self after initialisation to increase burnScore
        helper_initialize();

        uint256 mult = 1e6;
        uint256 amountSend = mult * ONE_TOKEN;

        uint256 balanceTreasury = cyberCash.balanceOf(treasury);
        uint256 burnScoreTreasury = cyberCash.burnScore(treasury);

        assertEq(balanceTreasury, INITIAL_SUPPLY);
        assertEq(burnScoreTreasury, 0);

        vm.startPrank(treasury);
        cyberCash.transfer(treasury, amountSend);

        uint256 burnedAmount = (amountSend * BURN_ON_TRANSFER) / BURN_PRECISION;

        balanceTreasury = cyberCash.balanceOf(treasury);
        burnScoreTreasury = cyberCash.burnScore(treasury);

        assertEq(balanceTreasury, INITIAL_SUPPLY - burnedAmount);
        assertEq(burnScoreTreasury, burnedAmount);

        console.log(burnedAmount);
        console.log(burnScoreTreasury);
    }
}
