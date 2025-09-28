// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import "../src/ArbitrageDetectorTrap.sol";
import "../src/ArbitrageResponse.sol";

contract ArbitrageDetectorTrapTest is Test {
    ArbitrageDetectorTrap public trap;
    ArbitrageResponse public response;
    
    function setUp() public {
        trap = new ArbitrageDetectorTrap();
        response = new ArbitrageResponse();
    }
    
    function test_Constructor() public {
        assertEq(trap.MIN_PRICE_GAP(), 50, "Minimum price gap should be 0.5%");
        assertEq(trap.MIN_LIQUIDITY(), 1000e18, "Minimum liquidity should be $1000");
        assertEq(trap.MAX_GAS_COST(), 50e18, "Maximum gas cost should be $50");
        assertEq(trap.MAX_SLIPPAGE(), 100, "Maximum slippage should be 1%");
        assertEq(trap.MIN_PERSISTENCE_BLOCKS(), 2, "Minimum persistence should be 2 blocks");
        assertEq(trap.MOCK_TOKEN(), 0x1111111111111111111111111111111111111111, "Mock token should be set");
    }
    
    function test_GetMockPrices() public {
        ArbitrageDetectorTrap.MockDEX[3] memory dexes = trap.getMockPrices();
        
        assertEq(dexes.length, 3, "Should have 3 mock DEXes");
        assertEq(dexes[0].name, "MockUni", "First DEX should be MockUni");
        assertEq(dexes[1].name, "MockSushi", "Second DEX should be MockSushi");
        assertEq(dexes[2].name, "MockPancake", "Third DEX should be MockPancake");
        
        // Check that all have the same token
        for (uint i = 0; i < 3; i++) {
            assertEq(dexes[i].token, trap.MOCK_TOKEN(), "All DEXes should use same mock token");
            assertGt(dexes[i].price, 0, "DEX price should be greater than 0");
            assertGt(dexes[i].totalLiquidity, 0, "DEX liquidity should be greater than 0");
        }
    }
    
    function test_Collect() public {
        bytes memory data = trap.collect();
        
        // Decode the collected data
        ArbitrageDetectorTrap.ArbitrageData memory decodedData = 
            abi.decode(data, (ArbitrageDetectorTrap.ArbitrageData));
        
        assertEq(decodedData.blockNumber, block.number, "Block number should match current block");
        assertEq(decodedData.gasPrice, tx.gasprice, "Gas price should match current tx gas price");
        assertEq(decodedData.dexPrices.length, 3, "Should have 3 DEX prices");
        
        // Check DEX data integrity
        for (uint i = 0; i < 3; i++) {
            assertGt(decodedData.dexPrices[i].price, 0, "DEX price should be positive");
            assertEq(decodedData.dexPrices[i].token, trap.MOCK_TOKEN(), "Token should match");
        }
    }
    
    function test_UpdateMockPrice() public {
        uint256 newPrice = 3100e18; // $3100
        
        // Get initial prices
        ArbitrageDetectorTrap.MockDEX[3] memory initialPrices = trap.getMockPrices();
        uint256 initialPrice = initialPrices[0].price;
        
        // Update price
        trap.updateMockPrice(0, newPrice);
        
        // Get updated prices
        ArbitrageDetectorTrap.MockDEX[3] memory updatedPrices = trap.getMockPrices();
        
        assertEq(updatedPrices[0].price, newPrice, "Price should be updated");
        assertNotEq(updatedPrices[0].price, initialPrice, "Price should have changed");
        assertEq(updatedPrices[0].lastUpdate, block.number, "Last update should be current block");
    }
    
    function test_UpdateMockPrice_InvalidIndex() public {
        vm.expectRevert("Invalid DEX index");
        trap.updateMockPrice(3, 3100e18); // Index 3 doesn't exist (only 0,1,2)
    }
    
    function test_Evaluate_InsufficientData() public {
        bytes[] memory data = new bytes[](0);
        bool shouldRespond = trap.evaluate(data);
        assertFalse(shouldRespond, "Should not respond with no data");
    }
    
    function test_Evaluate_SmallPriceGap() public {
        // Create small price differences (< 0.5%)
        trap.updateMockPrice(0, 3000e18); // $3000
        trap.updateMockPrice(1, 3005e18); // $3005 (0.17% difference)
        trap.updateMockPrice(2, 2998e18); // $2998 (0.07% difference)
        
        bytes memory data = trap.collect();
        bytes[] memory dataArray = new bytes[](1);
        dataArray[0] = data;
        
        bool shouldRespond = trap.evaluate(dataArray);
        assertFalse(shouldRespond, "Should not respond to small price gaps");
    }
    
    function test_Evaluate_LargePriceGap_SingleBlock() public {
        // Create large price differences (> 0.5%)
        trap.updateMockPrice(0, 3000e18); // $3000
        trap.updateMockPrice(1, 3200e18); // $3200 (6.7% difference)
        trap.updateMockPrice(2, 2900e18); // $2900 (3.3% difference)
        
        bytes memory data = trap.collect();
        bytes[] memory dataArray = new bytes[](1);
        dataArray[0] = data;
        
        bool shouldRespond = trap.evaluate(dataArray);
        // Should not respond because persistence condition requires 2+ blocks
        assertFalse(shouldRespond, "Should not respond without persistence");
    }
    
    function test_Evaluate_PersistentArbitrage() public {
        // Set up persistent arbitrage opportunity
        trap.updateMockPrice(0, 3000e18); // $3000
        trap.updateMockPrice(1, 3200e18); // $3200 (6.7% difference)
        trap.updateMockPrice(2, 2900e18); // $2900
        
        // Collect data for multiple blocks
        bytes[] memory dataArray = new bytes[](3);
        
        // Block 1
        dataArray[0] = trap.collect();
        vm.roll(block.number + 1);
        
        // Block 2 - opportunity still exists
        dataArray[1] = trap.collect();
        vm.roll(block.number + 1);
        
        // Block 3 - opportunity persists
        dataArray[2] = trap.collect();
        
        bool shouldRespond = trap.evaluate(dataArray);
        assertTrue(shouldRespond, "Should respond to persistent arbitrage opportunity");
    }
    
    function test_ResponseContract_Constructor() public {
        assertEq(response.getTotalOpportunities(), 0, "Should start with 0 opportunities");
        assertEq(response.getTotalProfitPotential(), 0, "Should start with 0 profit potential");
        assertEq(response.lastResponseBlock(), 0, "Should start with block 0");
    }
    
    function test_ResponseContract_ArbitrageDetected() public {
        string memory buyDEX = "MockUni";
        string memory sellDEX = "MockSushi";
        address token = trap.MOCK_TOKEN();
        uint256 priceDiff = 500; // 5%
        uint256 profitPot = 150e18; // $150
        
        // Expect event emission
        vm.expectEmit(true, true, true, true);
        emit ArbitrageResponse.ArbitrageDetected(
            buyDEX,
            sellDEX,
            token,
            priceDiff,
            profitPot,
            block.number,
            address(this)
        );
        
        response.arbitrageDetected(buyDEX, sellDEX, token, priceDiff, profitPot);
        
        // Check state updates
        assertEq(response.getTotalOpportunities(), 1, "Should have 1 opportunity");
        assertEq(response.getTotalProfitPotential(), profitPot, "Should track profit potential");
        assertEq(response.lastResponseBlock(), block.number, "Should update last response block");
        assertEq(response.lastResponder(), address(this), "Should track responder");
    }
    
    function test_ResponseContract_MultipleOpportunities() public {
        // Add multiple opportunities
        response.arbitrageDetected("MockUni", "MockSushi", trap.MOCK_TOKEN(), 300, 100e18);
        response.arbitrageDetected("MockSushi", "MockPancake", trap.MOCK_TOKEN(), 400, 200e18);
        
        vm.roll(block.number + 1); // Move to next block to avoid duplicate processing
        response.arbitrageDetected("MockUni", "MockPancake", trap.MOCK_TOKEN(), 600, 300e18);
        
        assertEq(response.getTotalOpportunities(), 3, "Should have 3 opportunities");
        assertEq(response.getTotalProfitPotential(), 600e18, "Should sum profit potential");
    }
    
    function test_ResponseContract_GetOpportunity() public {
        string memory buyDEX = "MockUni";
        string memory sellDEX = "MockSushi"; 
        uint256 priceDiff = 500;
        uint256 profitPot = 150e18;
        
        response.arbitrageDetected(buyDEX, sellDEX, trap.MOCK_TOKEN(), priceDiff, profitPot);
        
        ArbitrageResponse.ArbitrageOpportunity memory opp = response.getOpportunity(0);
        
        assertEq(opp.buyDEX, buyDEX, "Buy DEX should match");
        assertEq(opp.sellDEX, sellDEX, "Sell DEX should match");
        assertEq(opp.token, trap.MOCK_TOKEN(), "Token should match");
        assertEq(opp.priceDifference, priceDiff, "Price difference should match");
        assertEq(opp.profitPotential, profitPot, "Profit potential should match");
        assertEq(opp.detectedAt, block.number, "Detection block should match");
        assertEq(opp.detector, address(this), "Detector should match");
        assertFalse(opp.executed, "Should not be executed initially");
    }
    
    function test_ResponseContract_MarkExecuted() public {
        response.arbitrageDetected("MockUni", "MockSushi", trap.MOCK_TOKEN(), 500, 150e18);
        
        uint256 actualProfit = 120e18; // $120 actual profit
        
        // Expect event emission
        vm.expectEmit(true, false, false, true);
        emit ArbitrageResponse.OpportunityExecuted(0, actualProfit, address(this));
        
        response.markExecuted(0, actualProfit);
        
        ArbitrageResponse.ArbitrageOpportunity memory opp = response.getOpportunity(0);
        assertTrue(opp.executed, "Opportunity should be marked as executed");
    }
    
    function test_ResponseContract_MarkExecuted_InvalidId() public {
        vm.expectRevert("Invalid opportunity ID");
        response.markExecuted(0, 100e18); // No opportunities exist
    }
    
    function test_ResponseContract_PerformanceMetrics() public {
        // Add some opportunities
        response.arbitrageDetected("MockUni", "MockSushi", trap.MOCK_TOKEN(), 300, 100e18);
        
        vm.roll(block.number + 1);
        response.arbitrageDetected("MockSushi", "MockPancake", trap.MOCK_TOKEN(), 400, 200e18);
        
        (
            uint256 totalOpps,
            uint256 totalProfit,
            uint256 averageProfit,
            uint256 lastBlock,
            address lastDetector
        ) = response.getPerformanceMetrics();
        
        assertEq(totalOpps, 2, "Should have 2 total opportunities");
        assertEq(totalProfit, 300e18, "Should have $300 total profit potential");
        assertEq(averageProfit, 150e18, "Should have $150 average profit");
        assertEq(lastBlock, block.number, "Should track last block");
        assertEq(lastDetector, address(this), "Should track last detector");
    }
    
    function test_ResponseContract_GetRecentOpportunities() public {
        // Add 5 opportunities
        for (uint i = 0; i < 5; i++) {
            vm.roll(block.number + i);
            response.arbitrageDetected("MockUni", "MockSushi", trap.MOCK_TOKEN(), 300 + i * 100, (100 + i * 50) * 1e18);
        }
        
        // Get recent 3 opportunities
        ArbitrageResponse.ArbitrageOpportunity[] memory recent = response.getRecentOpportunities(3);
        
        assertEq(recent.length, 3, "Should return 3 recent opportunities");
        assertEq(recent[2].profitPotential, 300e18, "Last opportunity should be most recent");
        assertEq(recent[0].profitPotential, 100e18, "First opportunity should be oldest of the 3");
    }
    
    function test_ResponseContract_DuplicateBlockPrevention() public {
        response.arbitrageDetected("MockUni", "MockSushi", trap.MOCK_TOKEN(), 500, 150e18);
        
        // Try to process again in same block
        vm.expectRevert("Already processed this block");
        response.arbitrageDetected("MockSushi", "MockPancake", trap.MOCK_TOKEN(), 400, 100e18);
    }
    
    function test_Integration_EndToEnd() public {
        console.log("🧪 Running end-to-end integration test");
        
        // 1. Set up arbitrage opportunity
        trap.updateMockPrice(0, 3000e18); // MockUni: $3000
        trap.updateMockPrice(1, 3200e18); // MockSushi: $3200 (6.7% difference)
        trap.updateMockPrice(2, 2950e18); // MockPancake: $2950
        
        // 2. Collect data over multiple blocks for persistence
        bytes[] memory dataArray = new bytes[](3);
        
        dataArray[0] = trap.collect();
        vm.roll(block.number + 1);
        
        dataArray[1] = trap.collect();
        vm.roll(block.number + 1);
        
        dataArray[2] = trap.collect();
        
        // 3. Evaluate should return true
        bool shouldRespond = trap.evaluate(dataArray);
        assertTrue(shouldRespond, "Integration: Should detect persistent arbitrage");
        
        // 4. Simulate response (in real scenario, Drosera would call the response contract)
        response.arbitrageDetected("MockUni", "MockSushi", trap.MOCK_TOKEN(), 667, 200e18); // 6.67% difference, $200 profit
        
        // 5. Verify response was recorded
        assertEq(response.getTotalOpportunities(), 1, "Integration: Should record opportunity");
        assertEq(response.getTotalProfitPotential(), 200e18, "Integration: Should record profit potential");
        
        console.log("✅ Integration test completed successfully");
    }
}
