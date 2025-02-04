// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CyberCash} from "src/CyberCash.sol";
import {Migrator} from "src/Migrator.sol";

interface IWeth {
    function withdrawTo(address to, uint256 amount) external;
    function depositTo(address to) external payable;
}

// ============================================
// ==              CUSTOM ERRORS             ==
// ============================================
error NotOwner();
error ZeroAddress();

error ZeroAmount();
error TokenNotAllowed();
error IsAllowed();
error AlreadySet();
error InsufficientBurnScore();
error InvalidRatio();
error InvalidDecimals();
error NoBalanceAvailable();

contract MigratorTest is Test {
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

    // WETH on Arbitrum
    IWeth weth = IWeth(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);

    // time
    uint256 oneYear = 60 * 60 * 24 * 365;
    uint256 deployment;

    // Constants
    uint256 constant INITIAL_SUPPLY = 1e28; // 10 billion
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
    uint256 amountWETH = 1e19;

    //////////////////////////////////////
    /////// SETUP
    //////////////////////////////////////
    function setUp() public {
        // Create main net fork
        vm.createSelectFork({urlOrAlias: "alchemy_arbitrum_api", blockNumber: 260000000});

        // Create contract instances
        migrator = new Migrator(treasury);
        cyberCash = new CyberCash("CyberCash", "CASH", treasury);

        deployment = block.timestamp;

        vm.deal(Alice, 100 ether);
        vm.deal(Bob, 100 ether);
        vm.deal(treasury, 100 ether);
    }

    //////////////////////////////////////
    /////// HELPER FUNCTIONS
    //////////////////////////////////////
    // register the liquidity pool & migrator in the token contract
    function helper_initialize() public {
        vm.prank(treasury);
        cyberCash.initialize(liquidityPool, address(migrator));
    }

    // Set CyberCash address in migrator
    function helper_Migrator_setCashAddress() public {
        vm.prank(treasury);
        migrator.setCashAddress(address(cyberCash));
    }

    // List PSM for migration at ratio 1:1
    function helper_Migrator_addTokenMigration() public {
        vm.prank(treasury);
        migrator.addTokenMigration(psm, PSM_RATIO, PSM_DECIMALS);
    }
    //////////////////////////////////////
    /////// TESTS - Migrator
    //////////////////////////////////////
    // Owner sets the CASH address in Migrator

    function testSuccess_Migrator_setCashAddress() public {
        assertEq(address(migrator.cyberCash()), address(0));

        vm.prank(treasury);
        migrator.setCashAddress(address(cyberCash));

        assertEq(address(migrator.cyberCash()), address(cyberCash));
    }

    function testRevert_Migrator_setCashAddress() public {
        // Scenario 1: Revert if not owner
        vm.prank(Alice);
        vm.expectRevert(NotOwner.selector);
        migrator.setCashAddress(Alice);

        // Scenario 2: Revert if zero address
        vm.prank(treasury);
        vm.expectRevert(ZeroAddress.selector);
        migrator.setCashAddress(address(0));

        // Scenario 3: Revert if already set
        helper_Migrator_setCashAddress();
        vm.prank(treasury);
        vm.expectRevert(AlreadySet.selector);
        migrator.setCashAddress(address(cyberCash));
    }

    // Owner enables a token for migration
    function testSuccess_Migrator_addTokenMigration() public {
        uint256 cashLoad = 1000;

        assertEq(migrator.canMigrate(psm), false);

        helper_Migrator_setCashAddress();

        vm.prank(treasury);
        migrator.addTokenMigration(psm, PSM_RATIO, PSM_DECIMALS);

        assertEq(migrator.canMigrate(psm), true);

        // Load the migrator with 1000 CASH
        vm.prank(treasury);
        cyberCash.transfer(address(migrator), cashLoad);

        // simulate & verify a migration
        (uint256 spendPSM, uint256 receivedCASH) = migrator.migrationResult(address(psm), 1000);

        assertEq(spendPSM, cashLoad);
        assertEq(receivedCASH, cashLoad);
    }

    function testRevert_Migrator_addTokenMigration() public {
        // Scenario 1: Revert if not owner
        vm.prank(Alice);
        vm.expectRevert(NotOwner.selector);
        migrator.addTokenMigration(psm, PSM_RATIO, PSM_DECIMALS);

        // Scenario 2: Revert of zero address
        vm.startPrank(treasury);
        vm.expectRevert(ZeroAddress.selector);
        migrator.addTokenMigration(address(0), PSM_RATIO, PSM_DECIMALS);

        // Scenario 3: Revert if ratio is 0
        vm.expectRevert(InvalidRatio.selector);
        migrator.addTokenMigration(psm, 0, PSM_DECIMALS);

        // Scenario 4: Revert if decimalAdjustment is 0
        vm.expectRevert(InvalidDecimals.selector);
        migrator.addTokenMigration(psm, PSM_RATIO, 0);

        // Scenario 5: Revert if token already enabled
        migrator.addTokenMigration(psm, PSM_RATIO, PSM_DECIMALS);
        vm.expectRevert(IsAllowed.selector);
        migrator.addTokenMigration(psm, 111, PSM_DECIMALS);

        vm.stopPrank();
    }

    // Execute a migration
    function testSuccess_Migrator_migrate() public {
        uint256 cashLoad = 1e4;
        uint256 psmAmount = 1e6;
        uint256 migrationOne = 1e3;
        uint256 migrationTwo = 1e6;

        // set cybercash address and enable psm migration
        helper_Migrator_setCashAddress();
        helper_Migrator_addTokenMigration();
        helper_initialize();

        // treasury sends psm to alice
        vm.startPrank(treasury);
        IERC20(psm).transfer(Alice, psmAmount);

        // treasury sends CASH to the migrator
        cyberCash.transfer(address(migrator), cashLoad);
        vm.stopPrank();

        //Alice set approval
        vm.startPrank(Alice);
        IERC20(psm).approve(address(migrator), 1e55);

        // Scenario 1: Alice migrates 1k psm
        migrator.migrate(psm, migrationOne);

        assertEq(IERC20(psm).balanceOf(Alice), psmAmount - migrationOne);
        assertEq(cyberCash.balanceOf(Alice), migrationOne);

        // Scenario 2: Alice tries to migrate more than the remaining CASH balance in the migrator
        migrator.migrate(psm, migrationTwo);

        assertEq(IERC20(psm).balanceOf(Alice), psmAmount - cashLoad);
        assertEq(cyberCash.balanceOf(Alice), cashLoad);
        assertEq(cyberCash.balanceOf(address(migrator)), 0);
        assertEq(IERC20(psm).balanceOf(address(migrator)), cashLoad);

        vm.stopPrank();
    }

    function testRevert_Migrator_migrate() public {
        // Prepare token balances & settings
        uint256 psmToAlice = 1e6;
        uint256 cashToMigrator = 1e4;

        vm.startPrank(treasury);
        IERC20(psm).transfer(Alice, psmToAlice);
        cyberCash.transfer(address(migrator), cashToMigrator);
        vm.stopPrank();

        helper_Migrator_setCashAddress();
        helper_Migrator_addTokenMigration();

        // Scenario 1: Token is not allowed for migration
        vm.startPrank(Alice);
        IERC20(psm).approve(address(migrator), 1e55);

        vm.expectRevert(TokenNotAllowed.selector);
        migrator.migrate(address(0), 111);

        // Scenario 2: zero amount
        vm.expectRevert(ZeroAmount.selector);
        migrator.migrate(psm, 0);

        // Scenario 3: No CASH available in contract
        migrator.migrate(psm, psmToAlice);
        vm.expectRevert(NoBalanceAvailable.selector);
        migrator.migrate(psm, psmToAlice);
    }
}
