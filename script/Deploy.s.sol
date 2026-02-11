// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/CouncilPredictions.sol";

contract DeployCouncilPredictions is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy contract
        CouncilPredictions predictions = new CouncilPredictions();
        
        console.log("CouncilPredictions deployed at:", address(predictions));
        
        // Register bots (update with actual addresses)
        address botChad = vm.envAddress("BOT_CHAD_ADDRESS");
        address botQuantum = vm.envAddress("BOT_QUANTUM_ADDRESS");
        address botSensei = vm.envAddress("BOT_SENSEI_ADDRESS");
        address botSterling = vm.envAddress("BOT_STERLING_ADDRESS");
        address botOracle = vm.envAddress("BOT_ORACLE_ADDRESS");
        
        predictions.registerBot(botChad, "chad", 1);
        predictions.registerBot(botQuantum, "quantum", 2);
        predictions.registerBot(botSensei, "sensei", 3);
        predictions.registerBot(botSterling, "sterling", 4);
        predictions.registerBot(botOracle, "oracle", 5);
        
        console.log("Bots registered");
        
        // Set oracle (backend resolver)
        address oracleAddress = vm.envAddress("ORACLE_ADDRESS");
        predictions.setOracle(oracleAddress, true);
        
        console.log("Oracle set:", oracleAddress);
        
        vm.stopBroadcast();
    }
}

contract DeployCouncilPredictionsSimple is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        CouncilPredictions predictions = new CouncilPredictions();
        
        console.log("CouncilPredictions deployed at:", address(predictions));
        
        vm.stopBroadcast();
    }
}

contract RegisterBots is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address predictionsAddress = vm.envAddress("PREDICTIONS_CONTRACT");
        
        vm.startBroadcast(deployerPrivateKey);
        
        CouncilPredictions predictions = CouncilPredictions(payable(predictionsAddress));
        
        address botChad = vm.envAddress("BOT_CHAD_ADDRESS");
        address botQuantum = vm.envAddress("BOT_QUANTUM_ADDRESS");
        address botSensei = vm.envAddress("BOT_SENSEI_ADDRESS");
        address botSterling = vm.envAddress("BOT_STERLING_ADDRESS");
        address botOracle = vm.envAddress("BOT_ORACLE_ADDRESS");
        
        predictions.registerBot(botChad, "chad", 1);
        predictions.registerBot(botQuantum, "quantum", 2);
        predictions.registerBot(botSensei, "sensei", 3);
        predictions.registerBot(botSterling, "sterling", 4);
        predictions.registerBot(botOracle, "oracle", 5);
        
        console.log("All bots registered");
        
        vm.stopBroadcast();
    }
}

contract CreateTestPrediction is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address predictionsAddress = vm.envAddress("PREDICTIONS_CONTRACT");
        address tokenAddress = vm.envAddress("TOKEN_ADDRESS");
        
        vm.startBroadcast(deployerPrivateKey);
        
        CouncilPredictions predictions = CouncilPredictions(payable(predictionsAddress));
        
        // Create a BOT_ROI prediction
        string[] memory botOptions = new string[](5);
        botOptions[0] = "James (Chad)";
        botOptions[1] = "Keone (Quantum)";
        botOptions[2] = "Portdev (Sensei)";
        botOptions[3] = "Harpal (Sterling)";
        botOptions[4] = "Mike (Oracle)";
        
        uint256 predictionId = predictions.createPrediction(
            tokenAddress,
            "Which bot will have the highest ROI this week?",
            CouncilPredictions.PredictionType.BOT_ROI,
            7 days,
            botOptions
        );
        
        console.log("Created prediction:", predictionId);
        
        vm.stopBroadcast();
    }
}
