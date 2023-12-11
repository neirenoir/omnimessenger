// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import { OmniMessenger } from "contracts/omnimessenger/OmniMessenger.sol";
import { CREATE2Deployer } from "contracts/deployer/CREATE2Deployer.sol";
import { LinkTokenInterface } from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";

contract HelloWorld {
    string public constant hello = "helloworld!";
}

contract Test is Script {

    function run() external {

        //address linkToken = vm.envAddress("LINK_TOKEN_ADDRESS");
        LinkTokenInterface linkToken = LinkTokenInterface(address(0x779877A7B0D9E8603169DdbD7836e478b4624789));
        OmniMessenger omniMessenger = OmniMessenger(address(0x86aB30617573966352b4485271B66Da05a0ef177));
        CREATE2Deployer deployer = CREATE2Deployer(address(0xA4bcb5baD083Cec7D890C93bB4Ea537cFFAa679B));
        uint64 avaxSelector = 14767482510784806043;

        console.logBytes(
            abi.encode(
                avaxSelector, address(deployer), 
                abi.encodeWithSelector(
                    CREATE2Deployer.deploy.selector, 
                    bytes(type(HelloWorld).creationCode),
                    bytes32(0),
                    bytes("") 
                )
            )
        );

        vm.startBroadcast();



        linkToken.transferAndCall(
            address(omniMessenger), 15000000, 
            abi.encode(
                avaxSelector, 
                address(deployer), 
                abi.encodeWithSelector(
                    CREATE2Deployer.deploy.selector, 
                    bytes(type(HelloWorld).creationCode),
                    bytes32(0),
                    bytes("") 
                )
            )
        );

        vm.stopBroadcast();
    }
}
