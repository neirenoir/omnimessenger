// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import { CREATE2Deployer } from "contracts/deployer/CREATE2Deployer.sol";
import { OmniMessenger } from "contracts/omnimessenger/OmniMessenger.sol";
import { ContractSender } from "contracts/contractsender/ContractSender.sol";

contract Setup is Script {
    bytes32 constant OMNIMESSENGER_LABS_SALT = keccak256("labs.infrastructure.omnimessenger");

    function run() external {

        address ccipRouter = vm.envAddress("CCIP_ROUTER_ADDRESS");
        address linkToken = vm.envAddress("LINK_TOKEN_ADDRESS");
        //address self = vm.envAddress("DEPLOYMENT_ADDRESS");

        vm.startBroadcast();

        CREATE2Deployer deployer = new CREATE2Deployer();
        OmniMessenger omniMessenger = OmniMessenger(
            deployer.deploy(
                abi.encodePacked(type(OmniMessenger).creationCode), 
                OMNIMESSENGER_LABS_SALT, 
                abi.encodeWithSelector(
                    OmniMessenger.initialize.selector, linkToken, ccipRouter
                )
            )
        );

        ContractSender contractSender = 
            new ContractSender(address(omniMessenger), linkToken, address(deployer));

        console.log("CREATE2Deployer deployed at: %s", address(deployer));        
        console.log("OmniMessenger deployed at: %s", address(omniMessenger));
        console.log("ContractSender deployed at: %s", address(contractSender));

        vm.stopBroadcast();
    }
}
