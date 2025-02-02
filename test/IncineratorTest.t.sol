// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CyberCash} from "src/CyberCash.sol";
import {Incinerator} from "src/Incinerator.sol";
import {Migrator} from "src/Migrator.sol";

// ============================================
// ==              CUSTOM ERRORS             ==
// ============================================
error NotInitialized();
error ZeroAmount();
error ZeroAddress();

contract CyberCashTest is Test {
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

    // Incinerator instance
    Incinerator incinerator;

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
        incinerator = new Incinerator(address(cyberCash));

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

    //////////////////////////////////////
    /////// TESTS - CyberCash
    //////////////////////////////////////
    function testRevert_deploy() public {
        vm.expectRevert(ZeroAddress.selector);
        new Incinerator(address(0));
    }

    function testSuccess_burnLoop() public {
        // Scenario 1: interact with Incinerator after initialisation
        helper_initialize();

        uint256 mult = 1e6;
        uint256 amountSend = mult * ONE_TOKEN;

        uint256 balanceTreasury = cyberCash.balanceOf(treasury);
        uint256 balanceIncinerator = cyberCash.balanceOf(address(incinerator));
        uint256 burnScoreTreasury = cyberCash.burnScore(treasury);
        uint256 burnScoreIncinerator = cyberCash.burnScore(address(incinerator));

        assertEq(balanceTreasury, INITIAL_SUPPLY);
        assertEq(balanceIncinerator, 0);
        assertEq(burnScoreTreasury, 0);
        assertEq(burnScoreIncinerator, 0);

        vm.startPrank(treasury);
        cyberCash.approve(address(incinerator), 1e55);
        incinerator.burnLoop(amountSend);
        vm.stopPrank();

        uint256 burnStepOne = (amountSend * BURN_ON_TRANSFER) / BURN_PRECISION;
        uint256 burnStepTwo = ((amountSend - burnStepOne) * BURN_ON_TRANSFER) / BURN_PRECISION;

        balanceTreasury = cyberCash.balanceOf(treasury);
        balanceIncinerator = cyberCash.balanceOf(address(incinerator));
        burnScoreTreasury = cyberCash.burnScore(treasury);
        burnScoreIncinerator = cyberCash.burnScore(address(incinerator));

        assertEq(balanceTreasury, INITIAL_SUPPLY - burnStepOne - burnStepTwo);
        assertEq(balanceIncinerator, 0);
        assertEq(burnScoreTreasury, burnStepOne + burnStepTwo);
        assertEq(burnScoreIncinerator, 0);
    }

    function testRevert_burnLoop() public {
        uint256 amountSend = 1e6 * ONE_TOKEN;

        // Scenario 1: Not Initialized
        vm.startPrank(treasury);
        cyberCash.approve(address(incinerator), 1e55);
        vm.expectRevert(NotInitialized.selector);
        incinerator.burnLoop(amountSend);
        vm.stopPrank();

        // Scenario 2: Zero Amount
        helper_initialize();

        vm.startPrank(treasury);
        cyberCash.approve(address(incinerator), 1e55);
        vm.expectRevert(ZeroAmount.selector);
        incinerator.burnLoop(0);
        vm.stopPrank();
    }
}
