import { ethers } from "ethers";
import config from "../config";

export type Address = `0x${string}`;

const PRIVATE_KEY = process.env.PRIVATE_KEY as Address;
if (!PRIVATE_KEY || PRIVATE_KEY === "0x0") {
  throw new Error("PRIVATE_KEY env var is required");
}

const NETWORK = process.env.NETWORK || "mainnet";
if (NETWORK !== "mainnet") {
  throw new Error(`Unsupported network: ${NETWORK}. Only mainnet is supported.`);
}

export const chainId = 1;

export const rpc: string = process.env.MAINNET_RPC_URL || "http://localhost:8545";
export const MAX_FEE_PER_GAS_GWEI = Number(process.env.MAX_FEE_PER_GAS_GWEI || 0);
export const MIN_EOA_ETH = Number(process.env.MIN_EOA_ETH || 0);
export const DRY_RUN = process.env.DRY_RUN === "true";
export const SKIP_MERKL_CLAIM = process.env.SKIP_MERKL_CLAIM === "true";
export const SKIP_COMPOUND = process.env.SKIP_COMPOUND === "true";

export const provider = new ethers.JsonRpcProvider(rpc);
export const wallet = new ethers.Wallet(PRIVATE_KEY, provider);

function resolveContract(name: keyof typeof config.contracts) {
  const contract = config.contracts[name];
  const networkConfig = contract.network[chainId as keyof typeof contract.network];
  if (!networkConfig) {
    throw new Error(`No config for ${name} on chain ${chainId}`);
  }
  return { abi: contract.abi, address: networkConfig.address };
}

export const Distributor = resolveContract("Distributor");
export const AutoPounder = resolveContract("AutoPounder");
export const STAKVault = resolveContract("STAKVault");
export const merkleUrl = config.merkleUrl;
