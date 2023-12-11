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
    root_dir = os.path.dirname(os.path.abspath(__file__)) + "/.."
    
    with open("chain_data.json") as f:
        chain_data = json.load(f)

        if not "deploy_on" in chain_data or len(chain_data["deploy_on"]) == 0:
            print("FATAL: no chains to deploy on were defined")
            sys.exit(2)
        
        for chain in chain_data["deploy_on"]:
            data = chain_data[chain[0]][chain[1]]

            process = run_nix_develop_shell(
                root_dir,
                (
                    f"CCIP_ROUTER_ADDRESS={data['ccipRouter']} "
                    f"LINK_TOKEN_ADDRESS={data['linkToken']} "
                    f"forge test "
                    f"--fork-url '{data['rpc']}' "
                    f"-vvv"
                ),
                None
            )

            process.wait()

            if process.returncode != 0:
                print(f"FATAL: issue encountered while testing on {chain[0]}")
                sys.exit(3)