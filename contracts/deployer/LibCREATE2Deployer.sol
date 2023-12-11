// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.19;

library LibCREATE2Deployer {
    function computeAddressGeneric(
        address deployer, bytes32 salt, bytes32 creationCodeHash
    ) internal pure returns (address addr) {     
        assembly {
            let ptr := mload(0x40)

            mstore(add(ptr, 0x40), creationCodeHash)
            mstore(add(ptr, 0x20), salt)
            mstore(ptr, deployer)
            let start := add(ptr, 0x0b)
            mstore8(start, 0xff)
            addr := keccak256(start, 85)
        }
    }

    function computeAddressDryRun(
        address sender, address deployer, bytes32 salt, bytes memory bytecode
    ) internal pure returns (address addr) {
        bytes32 dryReSalt = reSalt(salt, sender);
        bytes32 creationCodeHash = keccak256(bytecode);
        
        return computeAddressGeneric(deployer, dryReSalt, creationCodeHash);
    }

    function computeAddressDryRunFromPayload(
        address sender, address deployer, bytes memory payload
    ) internal pure returns (address addr) {
        (bytes memory code, bytes32 salt, ) = destructureDeployPayload(payload);
        
        return computeAddressDryRun(sender, deployer, salt, code);
    }

    function destructureDeployPayload(
        bytes memory data
    ) internal pure returns (
        bytes memory code,
        bytes32 salt, 
        bytes memory initData
    ) {
        return abi.decode(data, (bytes, bytes32, bytes));
    }

    function reSalt(bytes32 salt, address sender) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(salt, sender));
    }
}