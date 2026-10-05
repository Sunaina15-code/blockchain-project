import { expect } from "chai";
import { network } from "hardhat";

const { ethers } = await network.connect();

// ---------- helpers ----------
async function increaseTime(seconds: number) {
  await ethers.provider.send("evm_increaseTime", [seconds]);
  await ethers.provider.send("evm_mine", []);
}

const sha = (text: string) => ethers.sha256(ethers.toUtf8Bytes(text));

// Merkle helpers: sorted-pair keccak256, matches MedicalRecords.verifyInclusion
function hashPair(a: string, b: string) {
  const [x, y] = a.toLowerCase() < b.toLowerCase() ? [a, b] : [b, a];
  return ethers.keccak256(ethers.concat([x, y]));
}
function buildLayers(leaves: string[]) {
  const layers: string[][] = [leaves];
  let level = leaves;
  while (level.length > 1) {
    const next: string[] = [];
    for (let i = 0; i < level.length; i += 2) {
      next.push(i + 1 < level.length ? hashPair(level[i], level[i + 1]) : level[i]);
    }
    layers.push(next);
    level = next;
  }
  return layers;
}
function proofFor(layers: string[][], index: number) {
  const proof: string[] = [];
  for (const layer of layers.slice(0, -1)) {
    const sibling = index ^ 1;
    if (sibling < layer.length) proof.push(layer[sibling]);
    index = Math.floor(index / 2);
  }
  return proof;
}

describe("MedicalRecords", function () {
  let contract: any;
  let admin: any, patient: any, doctor: any, stranger: any, g1: any, g2: any, g3: any;
  const fileHash = sha("encrypted-file-bytes");

  beforeEach(async function () {
    [admin, patient, doctor, stranger, g1, g2, g3] = await ethers.getSigners();
    contract = await ethers.deployContract("MedicalRecords");
    await contract.registerDoctor(doctor.address);
    await contract.connect(patient).addRecord("local-abc", fileHash);
  });

  describe("roles and access control (Exp 2)", function () {
    it("lets only the admin register doctors", async function () {
      await expect(contract.connect(stranger).registerDoctor(stranger.address))
        .to.be.revertedWith("Only admin");
    });

    it("lets the patient read their own record", async function () {
      const [cid, hash] = await contract.connect(patient).getRecord(0);
      expect(cid).to.equal("local-abc");
      expect(hash).to.equal(fileHash);
    });

    it("denies a doctor who was not granted access", async function () {
      await expect(contract.connect(doctor).getRecord(0)).to.be.revertedWith("Access denied");
    });

    it("allows access after grant, denies after revoke", async function () {
      await contract.connect(patient).grantAccess(0, doctor.address, 3600);
      expect((await contract.connect(doctor).getRecord(0))[0]).to.equal("local-abc");
      await contract.connect(patient).revokeAccess(0, doctor.address);
      await expect(contract.connect(doctor).getRecord(0)).to.be.revertedWith("Access denied");
    });

    it("denies access after the time limit expires", async function () {
      await contract.connect(patient).grantAccess(0, doctor.address, 100);
      await increaseTime(200);
      await expect(contract.connect(doctor).getRecord(0)).to.be.revertedWith("Access denied");
    });

    it("blocks non-owners and non-doctors", async function () {
      await expect(contract.connect(stranger).grantAccess(0, doctor.address, 60))
        .to.be.revertedWith("Not owner");
      await expect(contract.connect(patient).grantAccess(0, stranger.address, 60))
        .to.be.revertedWith("Not a doctor");
    });

    it("lists doctors with active access (loop + array)", async function () {
      await contract.connect(patient).grantAccess(0, doctor.address, 3600);
      const active = await contract
        .connect(patient)
        .activeDoctors(0, [doctor.address, stranger.address]);
      expect(active).to.deep.equal([doctor.address]);
    });

    it("writes an audit event when a doctor logs access", async function () {
      await contract.connect(patient).grantAccess(0, doctor.address, 3600);
      await expect(contract.connect(doctor).logAccess(0)).to.emit(contract, "RecordAccessed");
    });
  });

  describe("hashing and Merkle trees (Exp 1)", function () {
    beforeEach(async function () {
      await contract.connect(patient).grantAccess(0, doctor.address, 3600);
    });

    it("detects a tampered file", async function () {
      expect(await contract.connect(doctor).verifyRecord(0, fileHash)).to.equal(true);
      expect(await contract.connect(doctor).verifyRecord(0, sha("tampered"))).to.equal(false);
    });

    it("verifies Merkle inclusion proofs", async function () {
      const leaves = ["a", "b", "c", "d", "e"].map(sha);
      const layers = buildLayers(leaves);
      const root = layers[layers.length - 1][0];
      await contract.connect(patient).anchorMerkleRoot(root);

      expect(await contract.verifyInclusion(patient.address, leaves[2], proofFor(layers, 2))).to.equal(true);
      expect(await contract.verifyInclusion(patient.address, leaves[4], proofFor(layers, 4))).to.equal(true);
      expect(await contract.verifyInclusion(patient.address, sha("x"), proofFor(layers, 2))).to.equal(false);
    });
  });

  describe("payable consultation (Exp 4 / Exp 5)", function () {
    const fee = ethers.parseEther("0.01");

    beforeEach(async function () {
      await contract.connect(doctor).setConsultationFee(fee);
    });

    it("rejects underpayment", async function () {
      await expect(contract.connect(patient).bookConsultation(0, doctor.address, 60, { value: 1n }))
        .to.be.revertedWith("Insufficient fee");
    });

    it("credits the doctor, grants access, and lets the doctor withdraw once", async function () {
      await contract.connect(patient).bookConsultation(0, doctor.address, 3600, { value: fee });
      expect(await contract.pendingBalance(doctor.address)).to.equal(fee);
      expect((await contract.connect(doctor).getRecord(0))[0]).to.equal("local-abc");

      await expect(contract.connect(doctor).withdraw()).to.emit(contract, "Withdrawn");
      expect(await contract.pendingBalance(doctor.address)).to.equal(0n);
      await expect(contract.connect(doctor).withdraw()).to.be.revertedWith("Nothing to withdraw");
    });
  });

  describe("emergency access by guardian voting (Exp 3)", function () {
    beforeEach(async function () {
      await contract.connect(patient).setGuardians([g1.address, g2.address, g3.address]);
      await contract.connect(doctor).requestEmergency(0);
    });

    it("only guardians can vote, and only once", async function () {
      await expect(contract.connect(stranger).voteEmergency(0)).to.be.revertedWith("Not a guardian");
      await contract.connect(g1).voteEmergency(0);
      await expect(contract.connect(g1).voteEmergency(0)).to.be.revertedWith("Already voted");
    });

    it("grants access only after a majority votes", async function () {
      await contract.connect(g1).voteEmergency(0);
      await expect(contract.connect(doctor).getRecord(0)).to.be.revertedWith("Access denied");
      await contract.connect(g2).voteEmergency(0);
      expect((await contract.connect(doctor).getRecord(0))[0]).to.equal("local-abc");
    });

    it("closes voting after the window", async function () {
      await increaseTime(3700);
      await expect(contract.connect(g1).voteEmergency(0)).to.be.revertedWith("Voting closed");
    });
  });
});
