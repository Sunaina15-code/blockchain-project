<<<<<<< HEAD
# Medical Records Access Control using Blockchain

Patients own their records, doctors get time-limited access, and every grant, revoke and read is logged on-chain.
Files are encrypted off-chain; only a content id, a SHA-256 hash and permissions are stored on-chain.

## How each lab experiment maps to this project

| Exp | Lab topic | Where it appears in the project | How to demo it |
|---|---|---|---|
| 1 | Hashing, nonce, Merkle trees, tamper detection | `dataHash` stored per record, `verifyRecord()`, `anchorMerkleRoot()` + `verifyInclusion()`; `offchain/encrypt_store.py`; `scripts/tamper-demo.ts` | `npx hardhat run scripts/tamper-demo.ts` |
| 2 | Loops, arrays, inheritance | `RoleManager` (A) + `FeeVault` (B) -> `MedicalRecords` (C, multiple inheritance); `activeDoctors()` loops over an array | `npx hardhat test` |
| 3 | Voting system | Emergency access: patient sets guardians, a doctor requests access, guardians vote once each inside a time window, majority grants access (`setGuardians`, `requestEmergency`, `voteEmergency`) | tests under "emergency access" |
| 4 | Balance transfer / vending machine | `bookConsultation()` is `payable`, checks the fee, credits the doctor; `withdraw()` pays out | tests under "payable consultation" |
| 5 | MetaMask, Sepolia, Etherscan | Deploy to Sepolia and sign with MetaMask (see below) | Remix Injected Provider or `--network sepolia` |
| 6 | Geth private PoW network | Deploy the same contract to your Geth chain (chainId 12345) | `--network gethPow` |
| 7 | Ganache + Remix | Deploy to Ganache (port 7545) | `--network ganache` |
| 8 | Hyperledger Fabric case study | See "Platform choice" below | report section |
| 9 | Corda / Quorum / Ripple | See "Platform choice" below | report section |

## Files

```
contracts/RoleManager.sol      admin + doctor roles
contracts/FeeVault.sol         payable fees + withdraw
contracts/MedicalRecords.sol   main contract
test/MedicalRecords.ts         Hardhat tests
scripts/tamper-demo.ts         Exp 1 demo
ignition/modules/MedicalRecords.ts   deployment module
offchain/encrypt_store.py      encrypt, hash, verify, decrypt (pip install cryptography)
```

Delete the template's sample contract, test and Ignition module first (Counter files).

## Network setup (Exp 5, 6, 7)

Private and test chains need an older EVM target than the Hardhat default. Add `evmVersion: "london"` to the compiler settings in your existing config, and add the networks below.

```ts
import { configVariable } from "hardhat/config";

// inside defineConfig({ ... })
solidity: { /* keep your existing profiles, and add to the compiler settings: */
  // settings: { evmVersion: "london" }
},
networks: {
  ganache:  { type: "http", chainType: "l1", url: "http://127.0.0.1:7545", accounts: "remote" },
  gethPow:  { type: "http", chainType: "l1", url: "http://127.0.0.1:8545", chainId: 12345, accounts: "remote" },
  sepolia:  { type: "http", chainType: "l1",
              url: configVariable("SEPOLIA_RPC_URL"),
              accounts: [configVariable("SEPOLIA_PRIVATE_KEY")] },
},
```

Deploy:

```bash
npx hardhat ignition deploy ignition/modules/MedicalRecords.ts --network ganache
npx hardhat ignition deploy ignition/modules/MedicalRecords.ts --network gethPow
npx hardhat ignition deploy ignition/modules/MedicalRecords.ts --network sepolia
```

- **Ganache / Geth:** accounts are unlocked on the node. For Geth, unlock several accounts (`--unlock "addr1,addr2,addr3"`) so you can play admin, patient and doctor.
- **Sepolia:** `npx hardhat keystore set SEPOLIA_PRIVATE_KEY` and `SEPOLIA_RPC_URL`. Use a throwaway test wallet, never a wallet that holds real funds.
- **MetaMask route (Exp 5):** copy `MedicalRecords.sol`, `RoleManager.sol` and `FeeVault.sol` into Remix, choose Injected Provider - MetaMask on Sepolia, deploy, then show the transaction on Etherscan.

## Platform choice (Exp 8 and 9)

| Platform | Privacy | Consensus | Fit for medical records |
|---|---|---|---|
| Ethereum (this project) | Public by default, so only hashes and permissions go on-chain | PoS on mainnet, PoW on the lab's Geth 1.11.6 chain | Good for a transparent audit trail and for learning; gas cost and public data are the trade-offs |
| Hyperledger Fabric | Permissioned, channels and private data collections | Pluggable ordering service (Raft) | Strong fit for a consortium of hospitals: known identities (MSP/CA), per-channel privacy, no gas fees |
| Quorum | Permissioned Ethereum with private transactions | IBFT / QBFT / Raft | Reuses Solidity code; privacy between hospitals |
| Corda | Point-to-point, only involved parties see data | Notary-based | Good for bilateral agreements; JVM stack, not Solidity |
| Ripple (XRP Ledger) | Public ledger | Federated consensus | Built for payments, not record access control |

Suggested statement for the report: a production system would likely use a permissioned platform (Fabric or Quorum) so patient data stays inside a hospital consortium. This project uses Ethereum tooling to demonstrate the access-control logic, which ports directly to Quorum and is conceptually similar to Fabric chaincode.

## Limitations (mention in the report)

- Doctor-side decryption keys are shared out of band; a production system needs public-key key exchange.
- On-chain data is public on Ethereum, which is why only hashes and permissions are stored.
- Registered doctors are approved by a single admin address.
- Medical data is sensitive; real deployments must follow healthcare privacy law.
=======
# blockchain-project
>>>>>>> c83843f1f637139e953987d6a91def47b4ea21b7
