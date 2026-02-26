import { ethers } from "ethers";
import {
  wallet,
  provider,
  Distributor,
  AutoPounder,
  STAKVault,
  merkleUrl,
  MAX_FEE_PER_GAS_GWEI,
  MIN_EOA_ETH,
  DRY_RUN,
} from "./utils/helpers";

// ============================================
// Types
// ============================================

interface TokenClaim {
  amount: string;
  proof: string[];
}

interface MerkleData {
  merkleRoot: string;
  claims: {
    [account: string]: {
      tokens: {
        [token: string]: TokenClaim;
      };
    };
  };
}

// ============================================
// Helpers
// ============================================

async function ntfy(title: string, body: string, priority: string, tags: string) {
  fetch("https://ntfy.sh/yn-events", {
    method: "POST",
    body: body,
    headers: { Title: title, Priority: priority, Tags: tags },
  }).catch(() => {
    /* Do nothing */
  });
}

async function retry<T>(fn: () => Promise<T>, retries = 3, delay = 5000): Promise<T> {
  for (let i = 0; i < retries; i++) {
    try {
      return await fn();
    } catch (err) {
      if (i === retries - 1) throw err;
      console.log(`Retry ${i + 1}/${retries} after error: ${err}`);
      await new Promise((r) => setTimeout(r, delay));
    }
  }
  throw new Error("unreachable");
}

async function assertGasPrice(): Promise<boolean> {
  const gas = await provider.getFeeData();
  if (!gas || !gas.maxFeePerGas) {
    console.log("Error getting gas price");
    return false;
  }
  const ourMaxGasGwei = ethers.parseUnits(`${MAX_FEE_PER_GAS_GWEI}`, "gwei");
  const maxFeePerGas = ethers.formatUnits(gas.maxFeePerGas, "gwei");
  console.log(`maxFeePerGas: ${maxFeePerGas} gwei`);
  if (gas.maxFeePerGas > ourMaxGasGwei) {
    console.log("Gas is too expensive right now");
    return false;
  }
  return true;
}

async function assertMinEoaBalance(): Promise<boolean> {
  const walletBalance = await provider.getBalance(wallet.address);
  const requiredMinEth = ethers.parseEther(`${MIN_EOA_ETH}`);
  console.log(`Wallet balance: ${ethers.formatEther(walletBalance)} ETH`);
  if (walletBalance < requiredMinEth) {
    console.log("EOA does not have minimum ETH balance to proceed");
    return false;
  }
  return true;
}

// ============================================
// Core Logic
// ============================================

async function fetchMerkleData(): Promise<MerkleData> {
  console.log(`Fetching merkle data from ${merkleUrl}`);
  const response = await retry(() => fetch(merkleUrl));
  if (!response.ok) {
    throw new Error(`Failed to fetch merkle data: ${response.status} ${response.statusText}`);
  }
  return (await response.json()) as MerkleData;
}

async function claimRewards(merkleData: MerkleData): Promise<string[]> {
  const stakVaultAddress = ethers.getAddress(STAKVault.address);

  // Find the STAK vault entry - try both checksum and lowercase lookups
  const vaultClaim =
    merkleData.claims[stakVaultAddress] ||
    merkleData.claims[stakVaultAddress.toLowerCase()];

  if (!vaultClaim) {
    console.log("No rewards found for STAK vault in merkle data");
    return [];
  }

  const tokenAddresses = Object.keys(vaultClaim.tokens);
  console.log(`Found ${tokenAddresses.length} reward token(s) to claim`);

  const distributor = new ethers.Contract(
    ethers.getAddress(Distributor.address),
    Distributor.abi,
    wallet,
  );

  const claimedTokens: string[] = [];

  for (const tokenAddr of tokenAddresses) {
    const claim = vaultClaim.tokens[tokenAddr];
    const checksumToken = ethers.getAddress(tokenAddr);
    console.log(
      `Claiming token ${checksumToken}, amount: ${claim.amount}, proofs: ${claim.proof.length}`,
    );

    // Check what has already been claimed
    const alreadyClaimed: bigint = await distributor.claimed(checksumToken, stakVaultAddress);
    const totalClaimable = BigInt(claim.amount);

    if (alreadyClaimed >= totalClaimable) {
      console.log(`Token ${checksumToken} already fully claimed (${alreadyClaimed})`);
      continue;
    }

    // Query reward token balance before claim
    const erc20 = new ethers.Contract(checksumToken, STAKVault.abi, provider);
    const balanceBefore: bigint = await erc20.balanceOf(stakVaultAddress);
    console.log(`Balance before claim: ${balanceBefore}`);

    if (DRY_RUN) {
      console.log(`[DRY RUN] Would claim token ${checksumToken}, amount: ${claim.amount}`);
      claimedTokens.push(checksumToken);
      continue;
    }

    // Execute claim
    const tx = await retry(() =>
      distributor.claim(checksumToken, stakVaultAddress, claim.amount, claim.proof),
    );
    console.log(`Claim tx broadcast: ${tx.hash}`);
    const receipt = await tx.wait();
    console.log(
      `Claim confirmed at block ${receipt.blockNumber}, gasUsed: ${receipt.gasUsed}`,
    );

    // Verify delivery
    const balanceAfter: bigint = await erc20.balanceOf(stakVaultAddress);
    const delivered = balanceAfter - balanceBefore;
    console.log(`Balance after claim: ${balanceAfter} (delivered: ${delivered})`);

    if (delivered <= 0n) {
      console.log(`WARNING: No tokens delivered for ${checksumToken}`);
    }

    claimedTokens.push(checksumToken);
  }

  return claimedTokens;
}

async function compound(): Promise<void> {
  const autoPounder = new ethers.Contract(
    ethers.getAddress(AutoPounder.address),
    AutoPounder.abi,
    wallet,
  );

  console.log("Calling compound() on AutoPounder...");

  if (DRY_RUN) {
    console.log(`[DRY RUN] Would call compound() on AutoPounder at ${AutoPounder.address}`);
    return;
  }

  const tx = await retry(() => autoPounder.compound());
  console.log(`Compound tx broadcast: ${tx.hash}`);
  const receipt = await tx.wait();
  const txCost = receipt.gasUsed * receipt.gasPrice;
  console.log(
    `Compound confirmed at block ${receipt.blockNumber}, gasUsed: ${receipt.gasUsed}, ` +
      `gasPrice: ${ethers.formatUnits(receipt.gasPrice, "gwei")} gwei, ` +
      `tx cost: ${ethers.formatEther(txCost)} ETH`,
  );
}

// ============================================
// Main
// ============================================

async function main() {
  try {
    console.log("StakeDAO Keeper starting...");
    if (DRY_RUN) console.log("[DRY RUN] Mode enabled - no transactions will be sent");
    console.log(`Wallet: ${wallet.address}`);

    // Pre-flight checks
    if (!(await assertMinEoaBalance())) {
      process.exit(1);
    }
    if (MAX_FEE_PER_GAS_GWEI && !(await assertGasPrice())) {
      process.exit(1);
    }

    // Step 1: Fetch merkle data and claim rewards
    const merkleData = await fetchMerkleData();
    const claimedTokens = await claimRewards(merkleData);
    console.log(`Claimed ${claimedTokens.length} token(s)`);

    // Step 2: Compound rewards via AutoPounder
    await compound();

    console.log("StakeDAO Keeper completed successfully");
    await ntfy(
      "StakeDAO Keeper",
      `Claimed ${claimedTokens.length} token(s) and compounded`,
      "low",
      "white_check_mark",
    );
  } catch (err) {
    console.error("StakeDAO Keeper failed:", err);
    await ntfy("StakeDAO Keeper FAILED", `${err}`, "high", "rotating_light");
    process.exit(1);
  }
}

main();
