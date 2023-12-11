// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import { LibCREATE2Deployer } from "contracts/deployer/LibCREATE2Deployer.sol";

/// @notice Contract that allows contracts to be deployed to deterministic 
///     addresses via the use of the CREATE2 EVM opcode. 
/// @dev It is recommended to start "terraforming" a new chain by deploying 
///     this contract first.
contract CREATE2Deployer {
    event ContractDeployed(address addr);

    /*
     * @dev this function should deploy a contract at a deterministic address
     * given by:
     *  - This contract's address
     *  - The sender's address
     *  - The given byte`code` parameter
     *  - The given `salt` parameter
     * For a fully deterministic deployment of all subsequent contracts, it is
     * recommended to always deploy this contract as the first interaction 
     * (nonce 0) of the deployer address in every given chain. This should
     * ensure that the contracts always have the same addresses in all chains.
     *
     * For further reliability, you may want to deploy this contract at a 
     * chosen higher nonce to test any possible issues before commiting to
     * the chosen nonce.
     */
    function deploy(
        bytes memory code,
        bytes32 salt,
        bytes calldata initData
    ) external returns (address addr) {
        bytes32 reSalt = LibCREATE2Deployer.reSalt(salt, msg.sender);
        assembly {
            addr := create2(0, add(code, 0x20), mload(code), reSalt)
            if iszero(extcodesize(addr)) { revert(0, 0) }
        }

        if (initData.length != 0) {
            bool success;
            bytes memory err;
            (success, err) = addr.call(initData);
            require(success, string(err));
        }

        emit ContractDeployed(addr);
    }
}
