// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "lib/forge-std/src/Test.sol";
import { CREATE2Deployer } from "contracts/deployer/CREATE2Deployer.sol";
import { OmniMessenger } from "contracts/omnimessenger/OmniMessenger.sol";
import { ContractSender } from "contracts/contractsender/ContractSender.sol";
import { LinkTokenInterface } from "node_modules/@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import { Client } from "node_modules/@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import { IRouterClient } from "node_modules/@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";


contract MockOnTokenTransfer {
    address internal last;

    function onTokenTransfer(
        address from, uint256 amount, bytes calldata data
    ) external returns (bool success) {
        // APPEASE THE COMPILER WARNING GODS
        last = from;
        amount == amount;
        data.length == data.length;
        return true;
    }
}

contract Send is Test {
    using stdStorage for StdStorage;

    uint256 constant GAZILLION = 1e64;
    bytes32 constant OMNIMESSENGER_LABS_SALT = keccak256("labs.infrastructure.omnimessenger");
    address immutable ccipRouter = vm.envAddress("CCIP_ROUTER_ADDRESS");
    LinkTokenInterface immutable linkToken = LinkTokenInterface(vm.envAddress("LINK_TOKEN_ADDRESS"));
    uint64 constant AVAX_SELECTOR = 14767482510784806043;

    
    CREATE2Deployer public deployer;
    OmniMessenger public omniMessenger;

    function setUp() public {
        deployer = new CREATE2Deployer();
        omniMessenger = OmniMessenger(
            deployer.deploy(
                abi.encodePacked(type(OmniMessenger).creationCode), 
                OMNIMESSENGER_LABS_SALT, 
                abi.encodeWithSelector(
                    OmniMessenger.initialize.selector, linkToken, ccipRouter
                )
            )
        );

        stdstore
            .target(address(linkToken))
            .sig(LinkTokenInterface.balanceOf.selector)
            .with_key(address(this))
            .checked_write(GAZILLION); // give ourselves a gazillion LINK
    }

    function testMessengerParams() public {
        assertEq(omniMessenger.getRouter(), ccipRouter);
    }

    function testFakeBalance() public {
        assertEq(linkToken.balanceOf(address(this)), GAZILLION);
    }

    function testLinkTransfer() public {
        linkToken.transfer(address(0xdead), 10 ether);
        assertEq(linkToken.balanceOf(address(this)), GAZILLION - 10 ether);
    }

    function testLinkTransferAndCall() public {
        MockOnTokenTransfer nootNoot = new MockOnTokenTransfer();
        linkToken.transferAndCall(address(nootNoot), 10 ether, bytes(""));
    }

    ///

    // What do you MEAN "unsupportedDestinationChain"?
    function testFailRouterToAvalanche() public view {
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(address(0xdead)),
            data: abi.encode(bytes("")),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV1({gasLimit: 1 ether, strict: false})
            ),
            feeToken: address(linkToken)
        });

        IRouterClient(ccipRouter).getFee(AVAX_SELECTOR, message);
    }

    function testRouterToMatic() public view {
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(address(0xdead)),
            data: "",
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: "",
            feeToken: address(linkToken)
        });

        console.log("%s", IRouterClient(ccipRouter).getFee(12532609583862916517, message));
    }

    ///

    function testOmniMessengerFee() public {
        Client.EVM2AnyMessage memory message = 
            omniMessenger.constructMessage(address(0xdead), address(linkToken), address(0), bytes(""), 10000000 ether);
        uint256 feefees = omniMessenger.calculateMessageFees(12532609583862916517, message);
        console.log("%s", feefees);
        
        assertLt(feefees, 10000000 ether);
    }

    function testOmniMessengerCall() public {
        linkToken.transferAndCall(
            address(omniMessenger), 1e32, 
            abi.encode(
                12532609583862916517, 
                address(deployer), 
                abi.encodeWithSelector(
                    CREATE2Deployer.deploy.selector, 
                    bytes(type(MockOnTokenTransfer).creationCode),
                    bytes32(OMNIMESSENGER_LABS_SALT),
                    bytes("") 
                )
            )
        );
    }
}
