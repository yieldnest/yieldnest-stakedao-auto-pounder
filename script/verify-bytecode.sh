#!/bin/bash
set -e

# Verify AutoPounder bytecode on-chain matches compiled bytecode
# Usage: ./script/verify-bytecode.sh <DEPLOYED_ADDRESS>
#
# Requirements:
# - ETH_MAINNET_RPC_URL environment variable must be set
# - ETHERSCAN_API_KEY environment variable must be set

if [ -z "$1" ]; then
    echo "Usage: $0 <DEPLOYED_ADDRESS>"
    exit 1
fi

DEPLOYED_ADDRESS=$1

if [ -z "$ETH_MAINNET_RPC_URL" ]; then
    echo "Error: ETH_MAINNET_RPC_URL environment variable is not set"
    exit 1
fi

if [ -z "$ETHERSCAN_API_KEY" ]; then
    echo "Error: ETHERSCAN_API_KEY environment variable is not set"
    exit 1
fi

echo "Generating constructor args via forge script..."

# Run the ConstructorArgs script to generate the encoded constructor args
# The output contains "0x..." in the logs, extract it
CONSTRUCTOR_ARGS=$(forge script script/ConstructorArgs.s.sol:ConstructorArgs \
    --rpc-url "$ETH_MAINNET_RPC_URL" 2>&1 | grep -o '0x[0-9a-fA-F]\{64,\}')

if [ -z "$CONSTRUCTOR_ARGS" ]; then
    echo "Error: Failed to generate constructor args"
    exit 1
fi

echo "Constructor args: ${CONSTRUCTOR_ARGS:0:66}..."
echo ""
echo "Verifying bytecode..."

forge verify-bytecode \
    --rpc-url "$ETH_MAINNET_RPC_URL" \
    --etherscan-api-key "$ETHERSCAN_API_KEY" \
    --encoded-constructor-args "$CONSTRUCTOR_ARGS" \
    "$DEPLOYED_ADDRESS" \
    src/AutoPounder.sol:AutoPounder
