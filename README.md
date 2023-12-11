# OmniMessenger
Any message, any chain! If it worked, that is.

## Usage
You can try to deploy it with `multichain-deploy.py``. It should deploy on all 
chains, if you have gas. You can list the chains you want to deploy to in
`chain_data.json`'s "deploy_on" field.

## Running
Keep in mind that Sepolia > Avalanche doesn't seem to work with 1.0 routers.
`ccip_test.s.sol` is crude, but should try to deploy a mock smart contract
at Avalanche, if it worked. Haven't tested with other chains, but I am not
optimistic about the fork tests reporting Polygon Mumbai's 7e27 gas fees.

## To figure out
Not gonna lie, it is kind of impressive that I can get gas fees that cause 
math overflows. It seems the `getFee()` command calculates its cost depending
on what gas limit you feed it: the higher the gas limit you set, the more
expensive the fees get. One must imagine the OmniMessenger happy.