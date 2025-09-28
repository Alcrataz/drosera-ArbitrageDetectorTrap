// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Arbitrage Detector Trap
/// @notice Detects profitable cross-DEX arbitrage opportunities using 5 safety conditions
/// @dev Uses mock DEX data for testing, follows Drosera trap interface
contract ArbitrageDetectorTrap {
    
    // Configuration constants
    uint256 public constant MIN_PRICE_GAP = 50; // 0.5% minimum gap (basis points)
    uint256 public constant MIN_LIQUIDITY = 1000e18; // $1000 minimum liquidity
    uint256 public constant MAX_GAS_COST = 50e18; // $50 max gas cost
    uint256 public constant MAX_SLIPPAGE = 100; // 1% max slippage
    uint256 public constant MIN_PERSISTENCE_BLOCKS = 2; // Must last 2+ blocks
    
    // Mock token for testing
    address public constant MOCK_TOKEN = 0x1111111111111111111111111111111111111111;
    
    struct MockDEX {
        string name;
        address token;
        uint256 price;          // Price in wei (18 decimals)
        uint256 reserveA;       // Token reserves
        uint256 reserveB;       // ETH/USDC reserves  
        uint256 totalLiquidity; // Total liquidity USD
        uint256 lastUpdate;     // Block number
        uint256 volatility;     // Volatility factor 1-10
    }
    
    struct ArbitrageData {
        MockDEX[3] dexPrices;   // 3 mock DEXes
        uint256 blockNumber;
        uint256 gasPrice;
        bool[5] triggerConditions; // Track which conditions are met
    }
    
    // State for persistence tracking
    mapping(bytes32 => uint256) private opportunityFirstSeen;
    
    // Mock DEX data
    MockDEX[3] private mockDEXes;
    
    constructor() {
        // Initialize 3 mock DEXes with different characteristics
        mockDEXes[0] = MockDEX({
            name: "MockUni",
            token: MOCK_TOKEN,
            price: 3000e18,        // $3000 
            reserveA: 100e18,      // 100 tokens
            reserveB: 300000e18,   // $300k USDC
            totalLiquidity: 600000e18, // $600k total
            lastUpdate: block.number,
            volatility: 3          // Medium volatility
        });
        
        mockDEXes[1] = MockDEX({
            name: "MockSushi", 
            token: MOCK_TOKEN,
            price: 3005e18,        // $3005 (slight premium)
            reserveA: 80e18,       // 80 tokens  
            reserveB: 240400e18,   // $240.4k USDC
            totalLiquidity: 480800e18, // $480.8k total
            lastUpdate: block.number,
            volatility: 5          // Higher volatility
        });
        
        mockDEXes[2] = MockDEX({
            name: "MockPancake",
            token: MOCK_TOKEN, 
            price: 2995e18,        // $2995 (slight discount)
            reserveA: 120e18,      // 120 tokens
            reserveB: 359400e18,   // $359.4k USDC  
            totalLiquidity: 718800e18, // $718.8k total
            lastUpdate: block.number,
            volatility: 2          // Lower volatility
        });
    }
    
    /// @notice Main trap function - collects current market data
    /// @return Encoded arbitrage data for analysis
    function collect() external view returns (bytes memory) {
        // Get current mock prices (would be real DEX calls in production)
        MockDEX[3] memory currentPrices = getCurrentPrices();
        
        ArbitrageData memory data = ArbitrageData({
            dexPrices: currentPrices,
            blockNumber: block.number,
            gasPrice: tx.gasprice,
            triggerConditions: [false, false, false, false, false]
        });
        
        return abi.encode(data);
    }
    
    /// @notice Evaluate if arbitrage opportunity exists with all 5 safety conditions
    /// @param data Historical arbitrage data 
    /// @return Whether to trigger response
    function evaluate(bytes[] memory data) external returns (bool) {
        if (data.length == 0) return false;
        
        // Decode latest data
        ArbitrageData memory latest = abi.decode(data[data.length - 1], (ArbitrageData));
        
        // Check all 5 trigger conditions
        bool[5] memory conditions;
        
        // Condition 1: Price Gap > 0.5%
        conditions[0] = checkPriceGap(latest.dexPrices);
        
        // Condition 2: Sufficient Liquidity
        conditions[1] = checkSufficientLiquidity(latest.dexPrices);
        
        // Condition 3: Profit > Gas Costs
        conditions[2] = checkProfitability(latest.dexPrices, latest.gasPrice);
        
        // Condition 4: Low Slippage Risk
        conditions[3] = checkSlippageRisk(latest.dexPrices);
        
        // Condition 5: Multi-Block Persistence
        conditions[4] = checkPersistence(latest.dexPrices, data);
        
        // All conditions must be true for safe arbitrage
        return conditions[0] && conditions[1] && conditions[2] && conditions[3] && conditions[4];
    }
    
    /// @notice Condition 1: Check if price gap exceeds minimum threshold
    function checkPriceGap(MockDEX[3] memory dexes) internal pure returns (bool) {
        uint256 maxPrice = 0;
        uint256 minPrice = type(uint256).max;
        
        // Find highest and lowest prices
        for (uint i = 0; i < 3; i++) {
            if (dexes[i].price > maxPrice) maxPrice = dexes[i].price;
            if (dexes[i].price < minPrice) minPrice = dexes[i].price;
        }
        
        // Calculate percentage difference
        uint256 priceDiff = ((maxPrice - minPrice) * 10000) / minPrice; // Basis points
        
        return priceDiff >= MIN_PRICE_GAP;
    }
    
    /// @notice Condition 2: Ensure sufficient liquidity for meaningful trades
    function checkSufficientLiquidity(MockDEX[3] memory dexes) internal pure returns (bool) {
        // Both DEXes involved in arbitrage must have minimum liquidity
        for (uint i = 0; i < 3; i++) {
            if (dexes[i].totalLiquidity < MIN_LIQUIDITY) {
                return false;
            }
        }
        return true;
    }
    
    /// @notice Condition 3: Ensure profit exceeds gas costs
    function checkProfitability(MockDEX[3] memory dexes, uint256 gasPrice) internal pure returns (bool) {
        // Find best arbitrage pair
        uint256 maxProfit = 0;
        
        for (uint i = 0; i < 3; i++) {
            for (uint j = i + 1; j < 3; j++) {
                uint256 priceDiff = dexes[i].price > dexes[j].price ? 
                    dexes[i].price - dexes[j].price : 
                    dexes[j].price - dexes[i].price;
                
                // Conservative profit estimate (10% of smaller liquidity pool at price diff)
                uint256 availableLiq = dexes[i].totalLiquidity < dexes[j].totalLiquidity ?
                    dexes[i].totalLiquidity : dexes[j].totalLiquidity;
                    
                uint256 estimatedProfit = (availableLiq * priceDiff) / (dexes[i].price * 10);
                
                if (estimatedProfit > maxProfit) {
                    maxProfit = estimatedProfit;
                }
            }
        }
        
        // Estimate gas cost (400k gas * gasPrice * ETH price in USD)
        uint256 gasCostUSD = (400000 * gasPrice * 3000e18) / 1e18; // Assume $3000 ETH
        
        return maxProfit > gasCostUSD && maxProfit > MAX_GAS_COST;
    }
    
    /// @notice Condition 4: Ensure slippage won't kill the arbitrage
    function checkSlippageRisk(MockDEX[3] memory dexes) internal pure returns (bool) {
        // Check that reserves are balanced enough to handle trades
        for (uint i = 0; i < 3; i++) {
            // Reserve ratio should be reasonable (not extreme imbalances)
            uint256 ratio = (dexes[i].reserveA * 1000) / (dexes[i].reserveB / 1e18);
            
            // Ratio should be between 1:100 and 100:1 (reasonable balance)
            if (ratio < 10 || ratio > 10000) {
                return false;
            }
        }
        return true;
    }
    
    /// @notice Condition 5: Opportunity must persist across multiple blocks
    function checkPersistence(MockDEX[3] memory currentDexes, bytes[] memory historicalData) internal returns (bool) {
        if (historicalData.length < MIN_PERSISTENCE_BLOCKS) {
            return false;
        }
        
        // Create unique hash for this arbitrage opportunity
        bytes32 opportunityHash = keccak256(abi.encode(
            findBestArbitragePair(currentDexes)
        ));
        
        // Check if we've seen this opportunity before
        uint256 firstSeen = opportunityFirstSeen[opportunityHash];
        
        if (firstSeen == 0) {
            // First time seeing this opportunity
            opportunityFirstSeen[opportunityHash] = block.number;
            return false;
        }
        
        // Check if opportunity has persisted long enough
        return (block.number - firstSeen) >= MIN_PERSISTENCE_BLOCKS;
    }
    
    /// @notice Helper function to find best arbitrage pair
    function findBestArbitragePair(MockDEX[3] memory dexes) internal pure returns (uint256, uint256) {
        uint256 bestI = 0;
        uint256 bestJ = 1;
        uint256 maxDiff = 0;
        
        for (uint i = 0; i < 3; i++) {
            for (uint j = i + 1; j < 3; j++) {
                uint256 diff = dexes[i].price > dexes[j].price ? 
                    dexes[i].price - dexes[j].price :
                    dexes[j].price - dexes[i].price;
                    
                if (diff > maxDiff) {
                    maxDiff = diff;
                    bestI = i;
                    bestJ = j;
                }
            }
        }
        
        return (bestI, bestJ);
    }
    
    /// @notice Get current mock DEX prices (simulates real DEX calls)
    function getCurrentPrices() internal view returns (MockDEX[3] memory) {
        MockDEX[3] memory current = mockDEXes;
        
        // Simulate price evolution based on block number and volatility
        for (uint i = 0; i < 3; i++) {
            uint256 blocksSinceUpdate = block.number - current[i].lastUpdate;
            
            if (blocksSinceUpdate > 0) {
                // Create pseudo-random price movement
                uint256 seed = uint256(keccak256(abi.encodePacked(
                    block.number, 
                    block.timestamp,
                    i,
                    current[i].volatility
                )));
                
                // Price change percentage (0 to volatility * 2%)
                uint256 changePercent = seed % (current[i].volatility * 20);
                bool increase = (seed % 2) == 0;
                
                uint256 priceChange = (current[i].price * changePercent) / 1000;
                
                if (increase) {
                    current[i].price += priceChange;
                } else {
                    current[i].price = current[i].price > priceChange ? 
                        current[i].price - priceChange : current[i].price;
                }
                
                // Update reserves accordingly (simplified)
                current[i].reserveB = (current[i].reserveA * current[i].price) / 1e18;
                current[i].lastUpdate = block.number;
            }
        }
        
        return current;
    }
    
    /// @notice View function to get current mock prices for testing
    function getMockPrices() external view returns (MockDEX[3] memory) {
        return getCurrentPrices();
    }
    
    /// @notice Force price update for testing
    function updateMockPrice(uint256 dexIndex, uint256 newPrice) external {
        require(dexIndex < 3, "Invalid DEX index");
        mockDEXes[dexIndex].price = newPrice;
        mockDEXes[dexIndex].lastUpdate = block.number;
        
        // Update reserves accordingly
        mockDEXes[dexIndex].reserveB = (mockDEXes[dexIndex].reserveA * newPrice) / 1e18;
    }
}
