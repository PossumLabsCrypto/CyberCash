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
error NoBalanceAvailable();

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
    uint256 amountWETH = 1e19;

    //////////////////////////////////////
    /////// SETUP
    //////////////////////////////////////
    function setUp() public {
        // Create main net fork
        vm.createSelectFork({urlOrAlias: "alchemy_arbitrum_api", blockNumber: 260000000});

        // Create contract instances
        migrator = new Migrator(treasury);
        cyberCash = new CyberCash("CyberCash", "CASH", treasury, address(migrator));

        deployment = block.timestamp;

        vm.deal(Alice, 100 ether);
        vm.deal(Bob, 100 ether);
        vm.deal(treasury, 100 ether);
    }

    //////////////////////////////////////
    /////// HELPER FUNCTIONS
    //////////////////////////////////////
    // Add liquidity to the LP
    function helper_addLiquidity() public {
        vm.startPrank(treasury);
        weth.depositTo{value: amountWETH}(treasury);

        IERC20(address(weth)).approve(liquidityPool, 1e55);
        cyberCash.approve(liquidityPool, 1e55);
        vm.stopPrank();

        vm.startPrank(liquidityPool);
        IERC20(address(weth)).transferFrom(treasury, liquidityPool, amountWETH);
        cyberCash.transferFrom(treasury, liquidityPool, RESERVE_START);
        vm.stopPrank();
    }

    // register the liquidity pool in the token contract
    function helper_registerLiquidityPool() public {
        vm.prank(treasury);
        cyberCash.setPoolAddress(address(liquidityPool));
    }

    // Set CyberCash address in migrator
    function helper_Migrator_setCashAddress() public {
        vm.prank(treasury);
        migrator.setCashAddress(address(cyberCash));
    }

    // List PSM for migration at ratio 1:1
    function helper_Migrator_addTokenMigration() public {
        vm.prank(treasury);
        migrator.addTokenMigration(psm, 1000);
    }

    //////////////////////////////////////
    /////// TESTS - CyberCash
    //////////////////////////////////////
    function testSuccess_deployToken() public view {
        assertEq(cyberCash.totalSupply(), INITIAL_SUPPLY);
        assertEq(cyberCash.balanceOf(treasury), INITIAL_SUPPLY);
        assertEq(cyberCash.MINT_PER_SECOND(), MINT_PER_SECOND);
        assertEq(cyberCash.BURN_ON_TRANSFER(), BURN_ON_TRANSFER);
        assertEq(cyberCash.BURN_FROM_LP(), BURN_FROM_LP);
        assertEq(cyberCash.BURN_PRECISION(), BURN_PRECISION);
        assertEq(cyberCash.rewardsPerTokenBurned(), 0);
        assertEq(cyberCash.lastMintTime(), block.timestamp);
        assertEq(cyberCash.totalBurned(), 0);
    }

    ////////// LP REGISTRATION & PRELOAD
    // Register the liquidity pool in the token contract
    function testSuccess_registerLiquidityPool() public {
        assertEq(cyberCash.liquidityPool(), address(0));
        assertEq(cyberCash.owner(), treasury);

        vm.prank(treasury);
        cyberCash.setPoolAddress(address(liquidityPool));

        assertEq(cyberCash.liquidityPool(), address(liquidityPool));
        assertEq(cyberCash.owner(), address(0));
    }

    // Revert cases of LP registration
    function testRevert_registerLiquidityPool() public {
        assertEq(cyberCash.liquidityPool(), address(0));
        assertEq(cyberCash.owner(), treasury);

        // Attempt to register zero address as liquidity pool
        vm.prank(treasury);
        vm.expectRevert(ZeroAddress.selector);
        cyberCash.setPoolAddress(address(0));

        // Attempt a second registration of the liquidity pool
        helper_registerLiquidityPool();
        vm.expectRevert(NotOwner.selector);
        helper_registerLiquidityPool();
    }

    // Add liquidity without registering the LP
    function testSuccess_AddToLP() public {
        // setup the LP
        helper_addLiquidity(); // trigger burn, i.e. less arrive

        assertEq(
            cyberCash.balanceOf(address(liquidityPool)),
            (RESERVE_START * (BURN_PRECISION - BURN_ON_TRANSFER)) / BURN_PRECISION
        );
    }

    ////////// TRANSFER BETWEEN USERS
    // Transfer Tokens before the LP was set
    function testSuccess_transferBeforeRegisteredLP() public {
        // Scenario 1: Tx burn & reward minting, no LP burn
        uint256 totalSent;

        // transfer tokens
        vm.prank(treasury);
        cyberCash.transfer(Alice, ONE_TOKEN);
        totalSent += ONE_TOKEN;

        //balance checks
        assertEq(cyberCash.balanceOf(treasury), INITIAL_SUPPLY - totalSent);
        assertEq(cyberCash.balanceOf(Alice), (ONE_TOKEN * (BURN_PRECISION - BURN_ON_TRANSFER)) / BURN_PRECISION);
        assertTrue(cyberCash.totalSupply() >= INITIAL_SUPPLY - ((totalSent * BURN_ON_TRANSFER) / BURN_PRECISION));
    }

    // Transfer Tokens after the LP was set
    function testSuccess_transferAfterRegisteredLP() public {
        // Scenario 1: LP was registered but not seeded
        // Tx burn & reward minting, no LP burn
        uint256 mult = 1e6;
        uint256 amountSend = mult * ONE_TOKEN;

        // send tokens to Alice
        vm.prank(treasury);
        cyberCash.transfer(Alice, amountSend);

        // Calculate and verify effects
        uint256 balanceLP = cyberCash.balanceOf(liquidityPool);
        uint256 balanceTreasury = cyberCash.balanceOf(address(treasury));
        uint256 balanceAlice = cyberCash.balanceOf(Alice);

        assertEq(balanceLP, 0);
        assertEq(balanceTreasury, INITIAL_SUPPLY - amountSend);
        assertEq(balanceAlice, (amountSend * (BURN_PRECISION - BURN_ON_TRANSFER)) / BURN_PRECISION);

        // Scenario 2: wait some time to let rewards accrue, check rewards
        vm.warp(block.timestamp + oneYear);

        uint256 mint = MINT_PER_SECOND * oneYear;
        uint256 _totalBurned = (cyberCash.totalBurned() < REWARD_PRECISION) ? REWARD_PRECISION : cyberCash.totalBurned();
        uint256 simulatedRewardsPerTokenBurned =
            (cyberCash.rewardsPerTokenBurned() + mint * REWARD_PRECISION) / _totalBurned;

        uint256 treasuryBurned = cyberCash.burnScore(treasury);
        uint256 reward = (treasuryBurned * (simulatedRewardsPerTokenBurned - 0)) / REWARD_PRECISION;

        balanceTreasury += reward;
        uint256 balanceSum = balanceTreasury + balanceAlice;

        assertEq(balanceTreasury, cyberCash.balanceOf(treasury));
        assertTrue(balanceSum <= cyberCash.totalSupply());

        // Scenario 3: LP was registered and seeded
        // Tx burn & reward minting + LP burn
        // register the LP
        helper_registerLiquidityPool();
        helper_addLiquidity();

        balanceTreasury -= RESERVE_START;

        assertEq(balanceTreasury, cyberCash.balanceOf(treasury)); // verify reduction of balance
        assertEq(treasuryBurned, cyberCash.burnScore(treasury)); // verify that nothing was burned
        assertEq(RESERVE_START, cyberCash.balanceOf(liquidityPool)); // verify increase of balance in LP

        // Send tokens to Bob
        vm.prank(treasury);
        cyberCash.transfer(Bob, amountSend);

        uint256 txBurned = (amountSend * BURN_ON_TRANSFER) / BURN_PRECISION;
        uint256 lpBurned = (amountSend * BURN_FROM_LP) / BURN_PRECISION;
        treasuryBurned += txBurned;
        balanceLP += RESERVE_START - lpBurned;

        assertEq(balanceTreasury - amountSend, cyberCash.balanceOf(treasury)); // verify transfer & burn
        assertEq(amountSend - txBurned, cyberCash.balanceOf(Bob)); // verify tokens received
        assertEq(treasuryBurned, cyberCash.burnScore(treasury)); // verify burn increase
        assertEq(balanceLP, cyberCash.balanceOf(liquidityPool)); // verify LP balance burn

        assertTrue(
            cyberCash.totalSupply()
                >= cyberCash.balanceOf(treasury) + cyberCash.balanceOf(Alice) + cyberCash.balanceOf(Bob)
                    + cyberCash.balanceOf(liquidityPool)
        );

        // Scenario 4: test correct working of totalSupply()
        vm.warp(block.timestamp + oneYear);
        vm.prank(Alice);
        cyberCash.transfer(Bob, 1);

        assertTrue(
            cyberCash.totalSupply()
                >= cyberCash.balanceOf(treasury) + cyberCash.balanceOf(Alice) + cyberCash.balanceOf(Bob)
                    + cyberCash.balanceOf(liquidityPool)
        );
    }

    // Transfer tokens from the LP after it was set
    function testSuccess_TransferFromLP() public {
        uint256 wethIn = 1e18;
        uint256 cashOut = 1e26;
        uint256 approval = 1e55;

        // register the LP
        vm.prank(treasury);
        cyberCash.setPoolAddress(liquidityPool);

        // Add liquidity
        helper_addLiquidity();

        // Simulate buy order
        // deposit ETH to get WETH for Bob
        vm.startPrank(Bob);
        weth.depositTo{value: 1e18}(Bob);

        // Give approvals
        IERC20(address(weth)).approve(liquidityPool, approval);
        cyberCash.approve(liquidityPool, approval);
        vm.stopPrank();

        // Transfer WETH from Bob to LP and CASH from LP to Bob
        vm.startPrank(liquidityPool);
        IERC20(address(weth)).transferFrom(Bob, liquidityPool, wethIn);
        cyberCash.transfer(Bob, cashOut);

        // Verify state changes & no burn
        uint256 balanceBob = cyberCash.balanceOf(Bob);
        uint256 balanceLP = cyberCash.balanceOf(liquidityPool);
        uint256 wethBob = IERC20(address(weth)).balanceOf(Bob);
        uint256 wethLP = IERC20(address(weth)).balanceOf(liquidityPool);

        assertEq(balanceBob, cashOut);
        assertEq(wethLP, amountWETH + wethIn);
        assertEq(balanceLP, RESERVE_START - cashOut);
        assertEq(wethBob, 0);
    }

    // Transfer the burnScore from one user to another & verify new reward accrual
    function testSuccess_TransferBurnScore() public {
        uint256 amountSend = 1e21;

        // Step 1: Send tokens to Alice, treasury accrues burnScore
        vm.prank(treasury);
        cyberCash.transfer(Alice, amountSend);

        // Step 2: let rewards accrue
        vm.warp(block.timestamp + oneYear);

        uint256 mint = MINT_PER_SECOND * oneYear;
        uint256 _totalBurned = (cyberCash.totalBurned() < REWARD_PRECISION) ? REWARD_PRECISION : cyberCash.totalBurned();
        uint256 simulatedRewardsPerTokenBurned =
            (cyberCash.rewardsPerTokenBurned() + mint * REWARD_PRECISION) / _totalBurned;

        uint256 treasuryBurned = cyberCash.burnScore(treasury);
        uint256 reward = (treasuryBurned * (simulatedRewardsPerTokenBurned - 0)) / REWARD_PRECISION;

        uint256 balanceTreasury = INITIAL_SUPPLY - amountSend + reward;
        uint256 balanceSum = balanceTreasury + cyberCash.balanceOf(Alice);
        uint256 burnScoreTreasury = (amountSend * BURN_ON_TRANSFER) / BURN_PRECISION;

        assertEq(balanceTreasury, cyberCash.balanceOf(treasury));
        assertTrue(balanceSum <= cyberCash.totalSupply());
        assertEq(burnScoreTreasury, cyberCash.burnScore(treasury));

        // Step 3: Transfer burnScore to Bob
        vm.prank(treasury);
        cyberCash.transferBurnScore(Bob, burnScoreTreasury);

        assertEq(cyberCash.burnScore(treasury), 0);
        assertEq(cyberCash.burnScore(Bob), burnScoreTreasury);

        // Step 4: let rewards accrue & check
        vm.warp(block.timestamp + oneYear);

        mint = MINT_PER_SECOND * oneYear;
        _totalBurned = (cyberCash.totalBurned() < REWARD_PRECISION) ? REWARD_PRECISION : cyberCash.totalBurned();

        uint256 sim2RewardsPerTokenBurned = (cyberCash.rewardsPerTokenBurned() + mint * REWARD_PRECISION) / _totalBurned;

        reward = (treasuryBurned * (sim2RewardsPerTokenBurned - simulatedRewardsPerTokenBurned)) / REWARD_PRECISION;
        balanceSum = cyberCash.balanceOf(treasury) + cyberCash.balanceOf(Alice) + cyberCash.balanceOf(Bob);

        assertEq(balanceTreasury, cyberCash.balanceOf(treasury)); // No change
        assertEq(cyberCash.balanceOf(Bob), mint); // Bob earns ~1Bn
        assertTrue(cyberCash.totalSupply() >= balanceSum);
    }

    function testRevert_transferBurnScore() public {
        // Send tokens to Alice, treasury accrues burnScore
        uint256 amountSend = 1e20;
        vm.startPrank(treasury);
        cyberCash.transfer(Alice, amountSend);

        // Scenario 1: Zero address
        vm.expectRevert(ZeroAddress.selector);
        cyberCash.transferBurnScore(address(0), 1);

        // Scenario 2: Zero amount
        vm.expectRevert(ZeroAmount.selector);
        cyberCash.transferBurnScore(Bob, 0);

        // Scenario 3: Too large send amount
        uint256 invalidAmount = cyberCash.burnScore(treasury) + 1;
        vm.expectRevert(InsufficientBurnScore.selector);
        cyberCash.transferBurnScore(Bob, invalidAmount);
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
        assertEq(migrator.canMigrate(psm), false);

        helper_Migrator_setCashAddress();

        vm.prank(treasury);
        migrator.addTokenMigration(psm, 1000);

        assertEq(migrator.canMigrate(psm), true);

        vm.prank(treasury);
        cyberCash.transfer(address(migrator), 1000);

        (uint256 spendPSM, uint256 receivedCASH) = migrator.migrationResult(address(psm), 1000);

        assertEq(spendPSM, 1000);
        assertEq(receivedCASH, 1000);
    }

    function testRevert_Migrator_addTokenMigration() public {
        // Scenario 1: Revert if not owner
        vm.prank(Alice);
        vm.expectRevert(NotOwner.selector);
        migrator.addTokenMigration(psm, 1000);

        // Scenario 2: Revert of zero address
        vm.startPrank(treasury);
        vm.expectRevert(ZeroAddress.selector);
        migrator.addTokenMigration(address(0), 1000);

        // Scenario 3: Revert if ratio is 0
        vm.expectRevert(InvalidRatio.selector);
        migrator.addTokenMigration(psm, 0);

        // Scenario 4: Revert if token already enabled
        migrator.addTokenMigration(psm, 1000);
        vm.expectRevert(IsAllowed.selector);
        migrator.addTokenMigration(psm, 111);

        vm.stopPrank();
    }

    // Execute a migration
    function testSuccess_Migrator_migrate() public {
        uint256 cashLoad = 1e4;
        uint256 psmAmount = 1e6;
        uint256 migrationOne = 1e3;
        uint256 migrationTwo = 1e6;

        // treasury sends psm to alice
        vm.startPrank(treasury);
        IERC20(psm).transfer(Alice, psmAmount);

        // treasury sends CASH to the migrator
        cyberCash.transfer(address(migrator), cashLoad);
        vm.stopPrank();

        // set cybercash address and enable psm migration
        helper_Migrator_setCashAddress();
        helper_Migrator_addTokenMigration();

        //Alice set approval
        vm.startPrank(Alice);
        IERC20(psm).approve(address(migrator), 1e55);

        // Scenario 1: Alice migrates 1k psm in full
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
