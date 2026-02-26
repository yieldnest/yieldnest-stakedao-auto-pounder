
## Stake dao keeper


This code will be run by a cron 1-2 times a day.

it's a nodejs process

has a main function.

it queries 

https://raw.githubusercontent.com/stake-dao/merkl-toolkit/refs/heads/main/data/last_merkle.json

for any rewards available for the STAK vault ( 0xD1573de52fFF44dd92D275e20Fdab0296CCFF141  )

for those rewards what it does 

Is it calls claim.


The rewards distributor 0xd4898a378ea555595c4e7dbde722b134a3f346d1 is the target.

Example simulation

https://www.tdly.co/shared/simulation/96352d49-36ef-4e0d-8ce9-65ecd3e89dc2

You can find the claim function on etherscan for https://etherscan.io/address/0xd4898a378ea555595c4e7dbde722b134a3f346d1#writeContract

the proofs need to ve provided as shown in the json.



Once that is delivered, it then check the reward token was actually delivered to the target STAK vault (would be good to query the rewards tokens balance before)

then calls the autopounder contractt compound() function.

Keep in mind these addresses here should be nicely put in a file where they can be updated and marked as the ones for mainnet (chain id 1, living under that key somehow) and loaded accordingly.

Make this simple, DO NOT overcomplicate it.

You can follow the code patterns here:

https://github.com/yieldnest/ynethx-keeper/blob/main/src/main.ts

for abis and addrsses and logic.

add a bit of retry logic where it makes sense but fail if it doesn't succeded.

DO NOT overcomplicate.