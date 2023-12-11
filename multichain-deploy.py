#!/run/current-system/sw/bin/python
import json
import subprocess
import textwrap
import os, sys

# Function to run a command in a specific directory
def run_nix_develop_shell(directory, command, output=subprocess.DEVNULL):
    nix_develop_cmd = "nix develop"

    process = subprocess.Popen(
        f"{nix_develop_cmd} --command sh -c '{command}'",
        shell=True, 
        cwd=directory,
        stdout=output,
        stderr=subprocess.STDOUT
    )

    return process

# Main script logic
if __name__ == "__main__":
    if not "DEPLOYMENT_KEY" in os.environ or not "DEPLOYMENT_ADDRESS" in os.environ:
        print("FATAL: deployment key and/or address not specified")
        sys.exit(1)
    
    this_dir = os.path.dirname(os.path.abspath(__file__))
    deployment_key = os.environ["DEPLOYMENT_KEY"]
    deployment_sender = os.environ["DEPLOYMENT_ADDRESS"]

    deployment_script = "scripts/setup.s.sol:Setup"
    
    with open("chain_data.json") as f:
        chain_data = json.load(f)

        if not "deploy_on" in chain_data or len(chain_data["deploy_on"]) == 0:
            print("FATAL: no chains to deploy on were defined")
            sys.exit(2)
        
        for chain in chain_data["deploy_on"]:
            data = chain_data[chain[0]][chain[1]]

            process = run_nix_develop_shell(
                this_dir,
                (
                    f"CCIP_ROUTER_ADDRESS={data['ccipRouter']} "
                    f"LINK_TOKEN_ADDRESS={data['linkToken']} "
                    f"forge script {deployment_script} "
                    f"--rpc-url '{data['rpc']}' "
                    f"--broadcast "
                    f"--no-cache "
                    f"--sender {deployment_sender} "
                    f"--private-key {deployment_key} "
                ),
                None
            )

            process.wait()

            if process.returncode != 0:
                print(f"FATAL: issue encountered while deploying on {chain[0]}")
                sys.exit(3)