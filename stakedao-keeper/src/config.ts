import DistributorAbi from "./abis/Distributor.json";
import AutoPounderAbi from "./abis/AutoPounder.json";
import ERC20Abi from "./abis/ERC20.json";
import { Address } from "./utils/helpers";

export default {
  contracts: {
    Distributor: {
      abi: DistributorAbi,
      network: {
        1: {
          address: "0xd4898a378ea555595c4e7dbde722b134a3f346d1" as Address,
        },
      },
    },
    AutoPounder: {
      abi: AutoPounderAbi,
      network: {
        1: {
          address: "0xb96F35198E09E12a17c561D5f9Bc8595ECce94F6" as Address,
        },
      },
    },
    STAKVault: {
      abi: ERC20Abi,
      network: {
        1: {
          address: "0xD1573de52fFF44dd92D275e20Fdab0296CCFF141" as Address,
        },
      },
    },
  },
  merkleUrl:
    "https://raw.githubusercontent.com/stake-dao/merkl-toolkit/refs/heads/main/data/last_merkle.json",
};
