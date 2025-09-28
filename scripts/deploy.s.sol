// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import "../src/ArbitrageDetectorTrap.sol";
import "../src/ArbitrageResponse.sol";

contract Deploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy the Arbitrage Response Contract first
        ArbitrageResponse response = new ArbitrageResponse();
        console.log("ArbitrageResponse deployed at:", address(response));
        
        // Deploy the Arbitrage Detector Trap
        ArbitrageDetectorTrap trap = new ArbitrageDetectorTrap();
        console.log("ArbitrageDetectorTrap deployed at:", address(trap));
        
        vm.stopBroadcast();
        
        // Log deployment info for drosera.toml
        console.log("===============================================");
        console.log("Add this to your drosera.toml:");
        console.log("[deployment]");
        console.log("path = \"src/ArbitrageDetectorTrap.sol\"");
        console.log("address = \"%s\"", address(trap));
        console.log("response_contract = \"%s\"", address(response));
        console.log("response_function = \"arbitrageDetected(string,string,address,uint256,uint256)\"");
        console.log("===============================================");
        
        // Log useful contract info
        console.log("\nContract Details:");
        console.log("- Trap monitors 3 mock DEXes for arbitrage opportunities");
        console.log("- 5 safety conditions must be met before triggering");
        console.log("- Response contract tracks all opportunities and generates alerts");
        console.log("\nTest the deployment:");
        console.log("1. Check mock prices: trap.getMockPrices()");
        console.log("2. Force arbitrage: trap.updateMockPrice(0, 3200000000000000000000)");
        console.log("3. Monitor opportunities: response.getTotalOpportunities()");
    }
}
