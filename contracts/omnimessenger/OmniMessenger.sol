// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { ReentrancyGuard } from "@openzeppelin/security/ReentrancyGuard.sol";
import { IRouterClient } from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import { Client } from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import { LinkTokenInterface } from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import { CCIPReceiverLatebind } from "../utils/CCIPReceiverLatebind.sol";

/// @title - Send and receive calls from any chain, seamlessly!
contract OmniMessenger is CCIPReceiverLatebind, ReentrancyGuard {

    /*
     * region Errors
     */
    error NotEnoughBalance(uint256 currentBalance, uint256 calculatedFees); // Used to make sure contract has enough balance.
    error InvalidTokenTransfer(); // Used when onTokenTransfer is not called by the LINK contract
    /*
     * endregion
     */

    /*
     * region Events
     */
    // Event emitted when a message is sent to another chain.
    event MessageSent(
        bytes32 indexed messageId, // The unique ID of the CCIP message.
        uint64 indexed destinationChainSelector, // The chain selector of the destination chain.
        address indexed callTarget, // The address of the call target on the destination chain.
        bytes payload, // The payload being sent.
        uint256 fees // The fees paid for sending the CCIP message.
    );

    // Event emitted when a message is received from another chain.
    event MessageReceived(
        bytes32 indexed messageId, // The unique ID of the message.
        uint64 indexed sourceChainSelector, // The chain selector of the source chain.
        address sender, // The address of the sender from the source chain.
        address callTarget, // The target of the call
        bytes callPayload, // The contents of the call payload
        bool callSuccess, // The result of the call
        bytes callResult // Results of the call
    );

    event Initialized(address router, address linkToken);
    /*
     * endregion
     */

    // LINK token in this chain
    LinkTokenInterface internal linkToken;

    /// @dev it is EXTREMELY IMPORTANT you deploy this contract with a reproducible address
    constructor() { }

    /// @notice Initializes the contract with the router and LINK addresses.
    /// @param router The address of the router contract.
    /// @param link The address of the link contract.
    function initialize(address link, address router) public {
        if (address(linkToken) != address(0)) {
            revert AlreadyInitialized();
        }
        
        linkToken = LinkTokenInterface(link);
        setRouter(router);
        
        emit Initialized(router, link);
    }

    /*
     * region Sender
     */
    /// @notice Transform raw params into an EVM2AnyMessage construct
    /// @param receiver The address of the target contract (usually "this")
    /// @param feeToken The address of the link contract (usually LINK).
    /// @param callTarget The address of the contract to call in the destination chain
    /// @param payload The data to be passed to the callTarget via call()
    /// @param gasLimit self-explanatory. It shouldn't be __needed__, but it is.
    /// @return EVM2AnyMessage An EVM2AnyMessage object with the specified data.
    function constructMessage(
        address receiver, address feeToken,
        address callTarget, bytes memory payload, uint256 gasLimit
    ) public pure returns (Client.EVM2AnyMessage memory) {
        return Client.EVM2AnyMessage({
            receiver: abi.encode(receiver), // We expect the receiver to be this same contract
            data: abi.encode(callTarget, payload), // payload to be executed by the target
            tokenAmounts: new Client.EVMTokenAmount[](0), // Empty array indicating no tokens are being sent
            extraArgs: Client._argsToBytes(
                // Additional arguments, setting gas limit and non-strict sequencing mode
                Client.EVMExtraArgsV1({gasLimit: gasLimit, strict: false})
            ),
            // Set the feeToken  address, indicating LINK will be used for fees
            feeToken: feeToken
        });
    }

    /// @notice Sends data to receiver on the destination chain.
    /// @dev Assumes your contract has sufficient LINK.
    /// @param destinationChain The identifier (aka selector) for the destination blockchain.
    /// @param gasLimit The gas limit for this call
    /// @param payload The string text to be sent.
    /// @return messageId The ID of the message that was sent.
    /// @return fees The fees taken by the router.
    function _sendPayload(
        uint64 destinationChain,
        uint256 gasLimit,
        address callTarget,
        bytes memory payload
    ) internal returns (bytes32 messageId, uint256 fees) {
        // Get the router address from our own CCIPReceiver interface
        IRouterClient router = IRouterClient(this.getRouter());

        // Create an EVM2AnyMessage struct in memory with necessary information for sending a cross-chain message
        Client.EVM2AnyMessage memory message = 
            constructMessage(
                address(this), address(linkToken), callTarget, payload, gasLimit
            );

        // Get the fee required to send the message
        fees = calculateMessageFees(destinationChain, message);

        if (fees > gasLimit) {
            revert NotEnoughBalance(gasLimit, fees);
        }

        // approve the Router to transfer LINK tokens on contract's behalf. It will spend the fees in LINK
        linkToken.approve(address(router), fees);

        // Send the message through the router and store the returned message ID
        messageId = router.ccipSend(destinationChain, message);

        // Emit an event with message details
        emit MessageSent(
            messageId,
            destinationChain,
            callTarget,
            payload,
            fees
        );

        // Return the message ID
        return (messageId, fees);
    }


    /// @notice Destructures a bytes array as expected to be sent from the client via transferAndCall
    /// @param data The (uint64, address, bytes) payload
    /// @return destinationChain The destination chain selector.
    /// @return callTarget The destination chain recipient contract
    /// @return payload The data passed to callTarget.call()
    function destructureClientData(
        bytes calldata data
    ) internal pure returns (
        uint64 destinationChain, address callTarget, bytes memory payload
    ) {
        // We expect data to be structured the following way:
        //    uint64 destinationChainSelector
        //    address callTarget
        //    bytes payload (prepared to be used by _sendPayload)

        return abi.decode(data, (uint64, address, bytes));
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
        
        (uint64 destinationChain, address callTarget, bytes memory payload) =
            destructureClientData(data);

        ( , uint256 fees) = 
            _sendPayload(destinationChain, amount, callTarget, payload);

        if (amount > fees) {
            // We have some leftover LINK. Return to sender
            linkToken.transfer(from, amount - fees);
        }

        // Success!
        return true;
    }

    function _calculateMessageFees(
        uint64 destinationChain, Client.EVM2AnyMessage memory message
    ) view private returns (uint256) {
        return IRouterClient(this.getRouter()).getFee(destinationChain, message);
    }
    
    function calculateMessageFees(
        uint64 destinationChain, Client.EVM2AnyMessage memory message
    ) view public returns (uint256) {
        return _calculateMessageFees(destinationChain, message);
    }

    function calculateMessageFees(
        bytes calldata data
    ) external view returns (uint256) {
        (uint64 destinationChain, address callTarget, bytes memory payload) =
            destructureClientData(data);

        return _calculateMessageFees(
            destinationChain, 
            constructMessage(
                address(this), address(linkToken), 
                callTarget, payload, type(uint256).max
            )
        );
    }
    /*
     * endregion
     */

    /*
     * region Receiver
     */
    /// handle a received message
    function _ccipReceive(
        Client.Any2EVMMessage memory message
    ) internal override {
        (address callTarget, bytes memory payload) = 
            abi.decode(message.data, (address, bytes));
        (bool success, bytes memory result) = callTarget.call(payload);

        emit MessageReceived(
            message.messageId,
            message.sourceChainSelector,
            abi.decode(message.sender, (address)),
            callTarget, payload,
            success, result
        );
    }
     /*
      * endregion
      */
}