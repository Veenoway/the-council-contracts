// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/CouncilPredictions.sol";
import "../src/mocks/MockERC20.sol";

contract CouncilPredictionsTest is Test {
    CouncilPredictions public predictions;
    MockERC20 public token;
    
    address public owner = address(this);
    address public oracle = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    address public user3 = address(0x4);
    
    // Bot addresses
    address public botChad = address(0x100);
    address public botQuantum = address(0x101);
    address public botSensei = address(0x102);
    address public botSterling = address(0x103);
    address public botOracle = address(0x104);
    
    string[] public yesNoOptions;
    string[] public botOptions;
    
    function setUp() public {
        predictions = new CouncilPredictions();
        token = new MockERC20("Test Token", "TEST");
        
        // Setup oracle
        predictions.setOracle(oracle, true);
        
        // Mint tokens to users
        token.mint(user1, 1000 ether);
        token.mint(user2, 1000 ether);
        token.mint(user3, 1000 ether);
        
        // Fund users with MON
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(user3, 100 ether);
        
        // Fund bots
        vm.deal(botChad, 100 ether);
        vm.deal(botQuantum, 100 ether);
        vm.deal(botSensei, 100 ether);
        
        // Register bots
        predictions.registerBot(botChad, "chad", 1);
        predictions.registerBot(botQuantum, "quantum", 2);
        predictions.registerBot(botSensei, "sensei", 3);
        predictions.registerBot(botSterling, "sterling", 4);
        predictions.registerBot(botOracle, "oracle", 5);
        
        // Setup option arrays
        yesNoOptions = new string[](2);
        yesNoOptions[0] = "YES";
        yesNoOptions[1] = "NO";
        
        botOptions = new string[](5);
        botOptions[0] = "James (Chad)";
        botOptions[1] = "Keone (Quantum)";
        botOptions[2] = "Portdev (Sensei)";
        botOptions[3] = "Harpal (Sterling)";
        botOptions[4] = "Mike (Oracle)";
    }
    
    // ============================================================
    // CREATION TESTS
    // ============================================================
    
    function test_CreatePrediction() public {
        uint256 id = predictions.createPrediction(
            address(token),
            "Will $TEST pump 50%?",
            CouncilPredictions.PredictionType.PRICE,
            1 days,
            yesNoOptions
        );
        
        assertEq(id, 1);
        assertEq(predictions.predictionCount(), 1);
        
        (CouncilPredictions.Prediction memory p, ) = predictions.getPrediction(1);
        assertEq(p.question, "Will $TEST pump 50%?");
        assertEq(p.numOptions, 2);
        assertFalse(p.resolved);
    }
    
    function test_CreateBotROIPrediction() public {
        uint256 id = predictions.createPrediction(
            address(token),
            "Which bot will have highest ROI?",
            CouncilPredictions.PredictionType.BOT_ROI,
            7 days,
            botOptions
        );
        
        assertEq(id, 1);
        
        CouncilPredictions.PredictionView memory p = predictions.getPredictionFull(1);
        assertEq(uint8(p.predictionType), uint8(CouncilPredictions.PredictionType.BOT_ROI));
        assertEq(p.numOptions, 5);
    }
    
    function test_RevertWhen_CreatePredictionTooShort() public {
        vm.expectRevert("Duration too short");
        predictions.createPrediction(
            address(token),
            "Test?",
            CouncilPredictions.PredictionType.PRICE,
            30 minutes,
            yesNoOptions
        );
    }
    
    function test_RevertWhen_CreatePredictionTooFewOptions() public {
        string[] memory oneOption = new string[](1);
        oneOption[0] = "Only one";
        
        vm.expectRevert("Need at least 2 options");
        predictions.createPrediction(
            address(token),
            "Test?",
            CouncilPredictions.PredictionType.PRICE,
            1 days,
            oneOption
        );
    }
    
    // ============================================================
    // BETTING TESTS
    // ============================================================
    
    function test_PlaceBet() public {
        _createPricePrediction();
        
        vm.prank(user1);
        predictions.placeBet{value: 1 ether}(1, 1);
        
        (CouncilPredictions.Prediction memory p, CouncilPredictions.Option[] memory opts) = predictions.getPrediction(1);
        
        assertEq(p.prizePool, 1 ether);
        assertEq(p.totalBets, 1);
        assertEq(opts[0].totalStaked, 1 ether);
        assertEq(opts[0].numBettors, 1);
    }
    
    function test_MultipleBets() public {
        _createPricePrediction();
        
        vm.prank(user1);
        predictions.placeBet{value: 1 ether}(1, 1);
        
        vm.prank(user2);
        predictions.placeBet{value: 2 ether}(1, 2);
        
        vm.prank(user3);
        predictions.placeBet{value: 3 ether}(1, 1);
        
        (CouncilPredictions.Prediction memory p, CouncilPredictions.Option[] memory opts) = predictions.getPrediction(1);
        
        assertEq(p.prizePool, 6 ether);
        assertEq(p.totalBets, 3);
        assertEq(opts[0].totalStaked, 4 ether);
        assertEq(opts[1].totalStaked, 2 ether);
    }
    
    function test_RevertWhen_BetWithoutToken() public {
        _createPricePrediction();
        
        address noTokenUser = address(0x999);
        vm.deal(noTokenUser, 10 ether);
        
        vm.prank(noTokenUser);
        vm.expectRevert(CouncilPredictions.MustHoldToken.selector);
        predictions.placeBet{value: 1 ether}(1, 1);
    }
    
    function test_RevertWhen_DoubleBet() public {
        _createPricePrediction();
        
        vm.startPrank(user1);
        predictions.placeBet{value: 1 ether}(1, 1);
        
        vm.expectRevert(CouncilPredictions.AlreadyBet.selector);
        predictions.placeBet{value: 1 ether}(1, 2);
        vm.stopPrank();
    }
    
    function test_RevertWhen_BetTooSmall() public {
        _createPricePrediction();
        
        vm.prank(user1);
        vm.expectRevert(CouncilPredictions.BetTooSmall.selector);
        predictions.placeBet{value: 0.01 ether}(1, 1);
    }
    
    function test_RevertWhen_BetAfterEnd() public {
        _createPricePrediction();
        
        vm.warp(block.timestamp + 2 days);
        
        vm.prank(user1);
        vm.expectRevert(CouncilPredictions.BettingEnded.selector);
        predictions.placeBet{value: 1 ether}(1, 1);
    }
    
    // ============================================================
    // BOT BETTING TESTS
    // ============================================================
    
    function test_BotCanBet() public {
        _createPricePrediction();
        
        vm.prank(botChad);
        predictions.placeBet{value: 1 ether}(1, 1);
        
        CouncilPredictions.Bet memory bet = predictions.getUserBet(botChad, 1);
        assertEq(bet.amount, 1 ether);
    }
    
    function test_BotCanBetOnOtherBots() public {
        _createBotROIPrediction();
        
        vm.prank(botChad);
        predictions.placeBet{value: 1 ether}(1, 2);
        
        CouncilPredictions.Bet memory bet = predictions.getUserBet(botChad, 1);
        assertEq(bet.optionId, 2);
    }
    
    function test_RevertWhen_BotBetsOnSelf() public {
        _createBotROIPrediction();
        
        vm.prank(botChad);
        vm.expectRevert(CouncilPredictions.BotCannotBetOnSelf.selector);
        predictions.placeBet{value: 1 ether}(1, 1);
    }
    
    function test_BotCanBetOnSelfInPricePrediction() public {
        _createPricePrediction();
        
        vm.prank(botChad);
        predictions.placeBet{value: 1 ether}(1, 1);
        
        CouncilPredictions.Bet memory bet = predictions.getUserBet(botChad, 1);
        assertEq(bet.amount, 1 ether);
    }
    
    function test_CanBotBetOnOption() public {
        _createBotROIPrediction();
        
        (bool canBet, string memory reason) = predictions.canBotBetOnOption(botChad, 1, 1);
        assertFalse(canBet);
        assertEq(reason, "Bot cannot bet on itself");
        
        (canBet, reason) = predictions.canBotBetOnOption(botChad, 1, 2);
        assertTrue(canBet);
    }
    
    // ============================================================
    // RESOLUTION TESTS
    // ============================================================
    
    function test_ResolvePrediction() public {
        _createPricePrediction();
        
        vm.prank(user1);
        predictions.placeBet{value: 1 ether}(1, 1);
        
        vm.prank(user2);
        predictions.placeBet{value: 1 ether}(1, 2);
        
        vm.warp(block.timestamp + 2 days);
        
        vm.prank(oracle);
        predictions.resolvePrediction(1, 1);
        
        (CouncilPredictions.Prediction memory p, ) = predictions.getPrediction(1);
        assertTrue(p.resolved);
        assertEq(p.winningOption, 1);
    }
    
    function test_ResolvePredictionWithTie() public {
        _createBotROIPrediction();
        
        vm.prank(user1);
        predictions.placeBet{value: 1 ether}(1, 1);
        
        vm.prank(user2);
        predictions.placeBet{value: 1 ether}(1, 2);
        
        vm.warp(block.timestamp + 8 days);
        
        uint8[] memory tiedOptions = new uint8[](2);
        tiedOptions[0] = 1;
        tiedOptions[1] = 2;
        
        vm.prank(oracle);
        predictions.resolvePrediction(1, 1, true, tiedOptions);
        
        (CouncilPredictions.Prediction memory p, ) = predictions.getPrediction(1);
        assertTrue(p.resolved);
        assertTrue(p.isTie);
        
        uint8[] memory tied = predictions.getTiedWinningOptions(1);
        assertEq(tied.length, 2);
    }
    
    function test_RevertWhen_ResolveBeforeEnd() public {
        _createPricePrediction();
        
        vm.prank(oracle);
        vm.expectRevert(CouncilPredictions.BettingStillOpen.selector);
        predictions.resolvePrediction(1, 1);
    }
    
    function test_RevertWhen_ResolveNotOracle() public {
        _createPricePrediction();
        
        vm.warp(block.timestamp + 2 days);
        
        vm.prank(user1);
        vm.expectRevert(CouncilPredictions.NotOracle.selector);
        predictions.resolvePrediction(1, 1);
    }
    
    // ============================================================
    // CLAIM TESTS
    // ============================================================
    
    function test_ClaimWinnings() public {
        _createPricePrediction();
        
        vm.prank(user1);
        predictions.placeBet{value: 2 ether}(1, 1);
        
        vm.prank(user2);
        predictions.placeBet{value: 2 ether}(1, 2);
        
        vm.warp(block.timestamp + 2 days);
        
        vm.prank(oracle);
        predictions.resolvePrediction(1, 1);
        
        uint256 balanceBefore = user1.balance;
        
        vm.prank(user1);
        predictions.claimWinnings(1);
        
        uint256 balanceAfter = user1.balance;
        assertEq(balanceAfter - balanceBefore, 3.9 ether);
    }
    
    function test_ClaimWinningsMultipleWinners() public {
        _createPricePrediction();
        
        vm.prank(user1);
        predictions.placeBet{value: 1 ether}(1, 1);
        
        vm.prank(user2);
        predictions.placeBet{value: 3 ether}(1, 1);
        
        vm.prank(user3);
        predictions.placeBet{value: 4 ether}(1, 2);
        
        vm.warp(block.timestamp + 2 days);
        
        vm.prank(oracle);
        predictions.resolvePrediction(1, 1);
        
        uint256 balance1Before = user1.balance;
        vm.prank(user1);
        predictions.claimWinnings(1);
        assertEq(user1.balance - balance1Before, 1.95 ether);
        
        uint256 balance2Before = user2.balance;
        vm.prank(user2);
        predictions.claimWinnings(1);
        assertEq(user2.balance - balance2Before, 5.85 ether);
    }
    
    function test_RevertWhen_ClaimNotWinner() public {
        _createPricePrediction();
        
        vm.prank(user1);
        predictions.placeBet{value: 1 ether}(1, 1);
        
        vm.prank(user2);
        predictions.placeBet{value: 1 ether}(1, 2);
        
        vm.warp(block.timestamp + 2 days);
        
        vm.prank(oracle);
        predictions.resolvePrediction(1, 1);
        
        vm.prank(user2);
        vm.expectRevert(CouncilPredictions.NotWinner.selector);
        predictions.claimWinnings(1);
    }
    
    function test_RevertWhen_DoubleClaim() public {
        _createPricePrediction();
        
        vm.prank(user1);
        predictions.placeBet{value: 1 ether}(1, 1);
        
        vm.warp(block.timestamp + 2 days);
        
        vm.prank(oracle);
        predictions.resolvePrediction(1, 1);
        
        vm.startPrank(user1);
        predictions.claimWinnings(1);
        
        vm.expectRevert(CouncilPredictions.AlreadyClaimed.selector);
        predictions.claimWinnings(1);
        vm.stopPrank();
    }
    
    // ============================================================
    // CANCEL & REFUND TESTS
    // ============================================================
    
    function test_CancelAndRefund() public {
        _createPricePrediction();
        
        vm.prank(user1);
        predictions.placeBet{value: 5 ether}(1, 1);
        
        predictions.cancelPrediction(1);
        
        uint256 balanceBefore = user1.balance;
        
        vm.prank(user1);
        predictions.claimRefund(1);
        
        assertEq(user1.balance - balanceBefore, 5 ether);
    }
    
    // ============================================================
    // VIEW FUNCTIONS TESTS
    // ============================================================
    
    function test_GetLatestPredictions() public {
        _createPricePrediction();
        _createBotROIPrediction();
        
        predictions.createPrediction(
            address(token),
            "Third prediction?",
            CouncilPredictions.PredictionType.VOLUME,
            1 days,
            yesNoOptions
        );
        
        CouncilPredictions.PredictionView[] memory latest = predictions.getLatestPredictions(2);
        
        assertEq(latest.length, 2);
        assertEq(latest[0].id, 3);
        assertEq(latest[1].id, 2);
    }
    
    function test_GetUserStats() public {
        _createPricePrediction();
        
        vm.prank(user1);
        predictions.placeBet{value: 2 ether}(1, 1);
        
        vm.warp(block.timestamp + 2 days);
        
        vm.prank(oracle);
        predictions.resolvePrediction(1, 1);
        
        CouncilPredictions.UserStats memory stats = predictions.getUserStats(user1);
        
        assertEq(stats.totalBets, 1);
        assertEq(stats.totalStaked, 2 ether);
        assertEq(stats.claimableBets, 1);
    }
    
    function test_GetClaimablePredictions() public {
        _createPricePrediction();
        
        vm.prank(user1);
        predictions.placeBet{value: 1 ether}(1, 1);
        
        vm.warp(block.timestamp + 2 days);
        
        vm.prank(oracle);
        predictions.resolvePrediction(1, 1);
        
        uint256[] memory claimable = predictions.getClaimablePredictions(user1);
        
        assertEq(claimable.length, 1);
        assertEq(claimable[0], 1);
    }
    
    function test_GetAllOdds() public {
        _createPricePrediction();
        
        vm.prank(user1);
        predictions.placeBet{value: 1 ether}(1, 1);
        
        vm.prank(user2);
        predictions.placeBet{value: 3 ether}(1, 2);
        
        uint256[] memory odds = predictions.getAllOdds(1);
        
        assertEq(odds[0], 40000);
        assertEq(odds[1], 13333);
    }
    
    function test_CanBetDetailed() public {
        _createPricePrediction();
        
        (bool canBet, string memory reason) = predictions.canBetDetailed(user1, 1);
        assertTrue(canBet);
        assertEq(reason, "Can bet");
        
        vm.prank(user1);
        predictions.placeBet{value: 1 ether}(1, 1);
        
        (canBet, reason) = predictions.canBetDetailed(user1, 1);
        assertFalse(canBet);
        assertEq(reason, "Already placed a bet");
    }
    
    function test_GetGlobalStats() public {
        _createPricePrediction();
        _createBotROIPrediction();
        
        vm.prank(user1);
        predictions.placeBet{value: 5 ether}(1, 1);
        
        vm.prank(user2);
        predictions.placeBet{value: 3 ether}(2, 1);
        
        (
            uint256 totalPredictions,
            uint256 totalVolume,
            ,
            uint256 activeCount
        ) = predictions.getGlobalStats();
        
        assertEq(totalPredictions, 2);
        assertEq(totalVolume, 8 ether);
        assertEq(activeCount, 2);
    }
    
    // ============================================================
    // ADMIN TESTS
    // ============================================================
    
    function test_SetOracle() public {
        address newOracle = address(0x999);
        predictions.setOracle(newOracle, true);
        assertTrue(predictions.oracles(newOracle));
    }
    
    function test_WithdrawFees() public {
        _createPricePrediction();
        
        vm.prank(user1);
        predictions.placeBet{value: 4 ether}(1, 1);
        
        vm.warp(block.timestamp + 2 days);
        
        vm.prank(oracle);
        predictions.resolvePrediction(1, 1);
        
        uint256 balanceBefore = owner.balance;
        predictions.withdrawFees();
        
        assertEq(owner.balance - balanceBefore, 0.1 ether);
    }
    
    // ============================================================
    // HELPER FUNCTIONS
    // ============================================================
    
    function _createPricePrediction() internal returns (uint256) {
        return predictions.createPrediction(
            address(token),
            "Will $TEST pump 50%?",
            CouncilPredictions.PredictionType.PRICE,
            1 days,
            yesNoOptions
        );
    }
    
    function _createBotROIPrediction() internal returns (uint256) {
        return predictions.createPrediction(
            address(token),
            "Which bot will have highest ROI?",
            CouncilPredictions.PredictionType.BOT_ROI,
            7 days,
            botOptions
        );
    }
}
