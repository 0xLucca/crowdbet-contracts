// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/EventFactory.sol";

contract DeployEventFactory is Script {
    // Network configuration
    struct NetworkConfig {
        string name;
        uint256 chainId;
        address protocolFeePaymentAddress;
    }

    // Network configurations
    mapping(string => NetworkConfig) public networkConfigs;

    function setUp() public {
        // Flare Mainnet
        networkConfigs["flare"] = NetworkConfig({
            name: "Flare",
            chainId: 14,
            protocolFeePaymentAddress: vm.envAddress("PROTOCOL_FEE_ADDRESS")
        });

        // Coston2 Testnet
        networkConfigs["coston2"] = NetworkConfig({
            name: "Coston2",
            chainId: 114,
            protocolFeePaymentAddress: vm.envAddress("PROTOCOL_FEE_ADDRESS")
        });

        networkConfigs["sepolia"] = NetworkConfig({
            name: "Sepolia",
            chainId: 11155111,
            protocolFeePaymentAddress: vm.envAddress("PROTOCOL_FEE_ADDRESS")
        });

        networkConfigs["local"] = NetworkConfig({
            name: "Local",
            chainId: 31337,
            protocolFeePaymentAddress: vm.envAddress("LOCAL_PROTOCOL_FEE_ADDRESS")
        });
    }

    function run() external {
        string memory network = vm.envString("NETWORK");
        deployToNetwork(network);
    }

    function deployToNetwork(string memory network) public {
        NetworkConfig memory config = networkConfigs[network];
        
        require(config.chainId != 0, "Unsupported network");
        require(config.protocolFeePaymentAddress != address(0), "Protocol fee address not set");

        console.log("Deploying EventFactory to", config.name);
        console.log("Chain ID:", config.chainId);
        console.log("Protocol Fee Address:", config.protocolFeePaymentAddress);

        uint256 deployerPrivateKey;
        if (keccak256(abi.encodePacked(network)) == keccak256(abi.encodePacked("local"))) {
            deployerPrivateKey = vm.envUint("LOCAL_PRIVATE_KEY");
        } else {
            deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        }
        
        vm.startBroadcast(deployerPrivateKey);

        // Deploy EventFactory
        EventFactory eventFactory = new EventFactory(config.protocolFeePaymentAddress);

        vm.stopBroadcast();

        console.log("EventFactory deployed to:", address(eventFactory));
        console.log("Owner:", eventFactory.owner());
        console.log("Protocol Fee Payment Address:", eventFactory.protocolFeePaymentAddress());
        console.log("Max Fee Percentage:", eventFactory.maxFeePercentage());

        // Save deployment info
        //_saveDeployment(network, address(eventFactory), config);
    }

    // function _saveDeployment(string memory network, address eventFactory, NetworkConfig memory config) internal {
    //     string memory json = "deployment";
        
    //     vm.serializeString(json, "network", config.name);
    //     vm.serializeUint(json, "chainId", config.chainId);
    //     vm.serializeAddress(json, "eventFactory", eventFactory);
    //     vm.serializeAddress(json, "protocolFeePaymentAddress", config.protocolFeePaymentAddress);
    //     vm.serializeUint(json, "deployedAt", block.timestamp);
    //     string memory finalJson = vm.serializeUint(json, "blockNumber", block.number);

    //     string memory filename = string.concat("./deployments/", network, ".json");
    //     vm.writeJson(finalJson, filename);
        
    //     console.log("Deployment info saved to:", filename);
    // }

    // Helper function to get deployment address from saved file
    function getDeploymentAddress(string memory network) external view returns (address) {
        string memory filename = string.concat("./deployments/", network, ".json");
        string memory json = vm.readFile(filename);
        return vm.parseJsonAddress(json, ".eventFactory");
    }

    // Helper function to verify deployment integrity
    function verifyDeployment(string memory network) external view {
        NetworkConfig memory config = networkConfigs[network];
        require(config.chainId != 0, "Unsupported network");

        try this.getDeploymentAddress(network) returns (address deployedAddress) {
            console.log("EventFactory found at:", deployedAddress);
            
            // Additional checks can be added here
            // For example, checking if the contract code exists at the address
            // or verifying the owner and configuration
            
        } catch {
            console.log("No deployment found for network:", network);
        }
    }
}
