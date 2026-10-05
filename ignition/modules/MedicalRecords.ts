import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("MedicalRecordsModule", (m) => {
  const medicalRecords = m.contract("MedicalRecords");
  return { medicalRecords };
});
