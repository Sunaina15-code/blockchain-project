// Exp 1 demo: change one character of a file and watch the on-chain hash check fail.
// Run: npx hardhat run scripts/tamper-demo.ts
import { network } from "hardhat";

const { ethers } = await network.connect();
const [admin, patient] = await ethers.getSigners();

const contract = await ethers.deployContract("MedicalRecords");
await contract.waitForDeployment();

const original = "Blood report: Hb 13.2 g/dL";
const tampered = "Blood report: Hb 12.2 g/dL"; // one character changed
const hashOf = (t: string) => ethers.sha256(ethers.toUtf8Bytes(t));

console.log("Original hash :", hashOf(original));
console.log("Tampered hash :", hashOf(tampered));

await (await contract.connect(patient).addRecord("local-demo", hashOf(original))).wait();

console.log("verifyRecord(original):", await contract.connect(patient).verifyRecord(0, hashOf(original)));
console.log("verifyRecord(tampered):", await contract.connect(patient).verifyRecord(0, hashOf(tampered)));
