// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.19;

import { OmniMessenger } from "contracts/omnimessenger/OmniMessenger.sol";
import { LinkTokenInterface } from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import { ReentrancyGuard } from "@openzeppelin/security/ReentrancyGuard.sol";
import { CREATE2Deployer } from "contracts/deployer/CREATE2Deployer.sol";
import { LibCREATE2Deployer } from "contracts/deployer/LibCREATE2Deployer.sol";

/// @notice Utility to help send contracts through CCIP 
contract ContractSender is ReentrancyGuard {

    error EmptyBytecode();
    error IllegalSelfCall(bytes4 susSelector);
    error InvalidTokenTransfer(); // Used when onTokenTransfer is not called by the LINK contract

    event ContractDeploymentRequest(uint64 chainSelector, address addr);

    OmniMessenger public immutable omniMessenger;
    LinkTokenInterface public immutable linkToken;
    CREATE2Deployer public immutable create2Deployer;
    
    constructor (
        address _omniMessenger, address _linkToken, address _create2Deployer
    ) {
        omniMessenger = OmniMessenger(_omniMessenger);
        linkToken = LinkTokenInterface(_linkToken);
        create2Deployer = CREATE2Deployer(_create2Deployer);
    }


    function fromBytecode(
        bytes memory code,
        bytes32 salt,
        bytes memory initData
    ) public pure returns (bytes memory) {
        if (code.length == 0) {
            revert EmptyBytecode();
        }

        return abi.encode(code, salt, initData);        
    }

    function fromAddress(
        address copyTarget, 
        bytes32 salt, 
        bytes memory initData
    ) public view returns (bytes memory) {
        bytes memory copyBytecode = copyTarget.code;
        
        return fromBytecode(copyBytecode, salt, initData);
    }

    function destructureTransferData(
        bytes memory data
    ) internal pure returns (uint64 chainSelector, bytes memory payload) {
        return abi.decode(data, (uint64, bytes));
    }

    function onTokenTransfer(
        address from, uint256 amount, bytes calldata data
    ) external nonReentrant returns (bool success) {
        // Technically, there would be no harm in letting people call this
        // "illegally", but there is also no reason they should do so. We will 
        // actively defend against it.
        if (msg.sender != address(linkToken)) {
            revert InvalidTokenTransfer();
        }
        
        (uint64 chainSelector, bytes memory selfPayload) =
            destructureTransferData(data);

        // You are gonna have to bear with me here:
        // selfPayload supposedly contains the selector and parameters for a self-call
        // This should be perfectly safe since this function, the only
        // "exploitable" one, is nonReentrant.
        // All other functions should return valid bytecode
        (bool succ, bytes memory create2Payload) = address(this).call(selfPayload);
        if (!succ) {
            revert IllegalSelfCall(bytes4(data[:4]));
        }

        linkToken.transferAndCall(
            address(omniMessenger), 
            amount, 
            abi.encode(chainSelector, address(create2Deployer), create2Payload)
        );

        // We will try to precompute the contract deployed at the destination chain
        // The msg.sender calling our CREATE2Deployer at the destination
        // will be our OmniMessenger
        address targetContractAddress = 
            LibCREATE2Deployer.computeAddressDryRunFromPayload(
                address(omniMessenger), address(create2Deployer), create2Payload
            );

        emit ContractDeploymentRequest(chainSelector, targetContractAddress);

        uint256 selfBalance = linkToken.balanceOf(address(this));
        if (selfBalance != 0) {
            linkToken.transfer(from, selfBalance);
        }

        // Success!
        return true;
    }
}
