// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./RoleManager.sol";
import "./FeeVault.sol";

/// @title MedicalRecords
/// @notice Access control for medical records. Files are encrypted and stored off-chain;
///         only a content id, a SHA-256 hash and permissions live on-chain.
/// @dev Multiple inheritance (Exp 2): RoleManager + FeeVault.
contract MedicalRecords is RoleManager, FeeVault {
    struct Record {
        string cid;        // off-chain content id (IPFS CID or local id)
        bytes32 dataHash;  // SHA-256 of the stored (encrypted) file  -> Exp 1
        address patient;
        uint256 timestamp;
    }

    struct EmergencyRequest {
        address doctor;
        uint256 recordId;
        uint256 votes;
        uint256 deadline;
        bool granted;
    }

    uint256 public constant EMERGENCY_VOTE_WINDOW = 1 hours;
    uint256 public constant EMERGENCY_ACCESS_DURATION = 1 hours;
    uint256 public constant MAX_GUARDIANS = 5;

    Record[] private records;
    mapping(address => uint256[]) private patientRecordIds;
    mapping(uint256 => mapping(address => uint256)) public access; // recordId => doctor => expiry
    mapping(address => bytes32) public merkleRoot;                  // patient => anchored root (Exp 1)

    // Emergency access by guardian voting (Exp 3)
    mapping(address => address[]) private guardians;
    mapping(address => mapping(address => bool)) public isGuardianOf; // patient => guardian
    EmergencyRequest[] private emergencies;
    mapping(uint256 => mapping(address => bool)) private hasVoted;    // requestId => guardian

    event RecordAdded(uint256 indexed id, address indexed patient, bytes32 dataHash);
    event AccessGranted(uint256 indexed id, address indexed doctor, uint256 expiry);
    event AccessRevoked(uint256 indexed id, address indexed doctor);
    event RecordAccessed(uint256 indexed id, address indexed viewer, uint256 time);
    event MerkleRootAnchored(address indexed patient, bytes32 root);
    event GuardiansSet(address indexed patient, uint256 count);
    event EmergencyRequested(uint256 indexed requestId, uint256 indexed recordId, address indexed doctor);
    event EmergencyVote(uint256 indexed requestId, address indexed guardian, uint256 votes);
    event EmergencyGranted(uint256 indexed requestId, uint256 indexed recordId, address indexed doctor, uint256 expiry);

    modifier validRecord(uint256 id) {
        require(id < records.length, "Invalid record");
        _;
    }

    modifier onlyPatientOf(uint256 id) {
        require(records[id].patient == msg.sender, "Not owner");
        _;
    }

    // ------------------------------------------------------------------ records

    function addRecord(string calldata cid, bytes32 dataHash) external returns (uint256) {
        require(bytes(cid).length > 0, "Empty cid");
        records.push(Record(cid, dataHash, msg.sender, block.timestamp));
        uint256 id = records.length - 1;
        patientRecordIds[msg.sender].push(id);
        emit RecordAdded(id, msg.sender, dataHash);
        return id;
    }

    function recordCount() external view returns (uint256) {
        return records.length;
    }

    function getMyRecordIds() external view returns (uint256[] memory) {
        return patientRecordIds[msg.sender];
    }

    // ------------------------------------------------------------------- access

    function _grant(uint256 id, address doctor, uint256 duration) internal {
        uint256 expiry = block.timestamp + duration;
        access[id][doctor] = expiry;
        emit AccessGranted(id, doctor, expiry);
    }

    function grantAccess(uint256 id, address doctor, uint256 duration)
        external
        validRecord(id)
        onlyPatientOf(id)
    {
        require(isDoctor[doctor], "Not a doctor");
        require(duration > 0, "Zero duration");
        _grant(id, doctor, duration);
    }

    function revokeAccess(uint256 id, address doctor) external validRecord(id) onlyPatientOf(id) {
        access[id][doctor] = 0;
        emit AccessRevoked(id, doctor);
    }

    function hasAccess(uint256 id, address user) public view validRecord(id) returns (bool) {
        return user == records[id].patient || access[id][user] > block.timestamp;
    }

    /// @notice Free read (no transaction). Returns the content id and hash.
    function getRecord(uint256 id) external view returns (string memory cid, bytes32 dataHash) {
        require(hasAccess(id, msg.sender), "Access denied");
        Record storage r = records[id];
        return (r.cid, r.dataHash);
    }

    /// @notice Transaction that writes an audit-log entry.
    function logAccess(uint256 id) external {
        require(hasAccess(id, msg.sender), "Access denied");
        emit RecordAccessed(id, msg.sender, block.timestamp);
    }

    /// @notice Loop + array example (Exp 2): which of `candidates` currently have access?
    function activeDoctors(uint256 id, address[] calldata candidates)
        external
        view
        validRecord(id)
        onlyPatientOf(id)
        returns (address[] memory)
    {
        uint256 count = 0;
        for (uint256 i = 0; i < candidates.length; i++) {
            if (access[id][candidates[i]] > block.timestamp) count++;
        }
        address[] memory result = new address[](count);
        uint256 j = 0;
        for (uint256 i = 0; i < candidates.length; i++) {
            if (access[id][candidates[i]] > block.timestamp) {
                result[j] = candidates[i];
                j++;
            }
        }
        return result;
    }

    // ---------------------------------------------------- payable (Exp 4 / Exp 5)

    function setConsultationFee(uint256 fee) external onlyDoctor {
        consultationFee[msg.sender] = fee;
        emit FeeSet(msg.sender, fee);
    }

    /// @notice Patient pays the doctor's fee and access is granted in one step.
    function bookConsultation(uint256 id, address doctor, uint256 duration)
        external
        payable
        validRecord(id)
        onlyPatientOf(id)
    {
        require(isDoctor[doctor], "Not a doctor");
        require(duration > 0, "Zero duration");
        require(msg.value >= consultationFee[doctor], "Insufficient fee");
        _credit(doctor);
        emit FeePaid(msg.sender, doctor, msg.value);
        _grant(id, doctor, duration);
    }

    // --------------------------------------------------- integrity (Exp 1)

    /// @notice True if `hash` equals the hash stored when the record was added.
    function verifyRecord(uint256 id, bytes32 hash) external view returns (bool) {
        require(hasAccess(id, msg.sender), "Access denied");
        return records[id].dataHash == hash;
    }

    /// @notice Anchor the Merkle root of all of the caller's record hashes.
    function anchorMerkleRoot(bytes32 root) external {
        merkleRoot[msg.sender] = root;
        emit MerkleRootAnchored(msg.sender, root);
    }

    /// @notice Verify a leaf belongs to the patient's anchored root (sorted-pair keccak256).
    function verifyInclusion(address patient, bytes32 leaf, bytes32[] calldata proof)
        external
        view
        returns (bool)
    {
        bytes32 computed = leaf;
        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 p = proof[i];
            computed = computed < p
                ? keccak256(abi.encodePacked(computed, p))
                : keccak256(abi.encodePacked(p, computed));
        }
        return computed == merkleRoot[patient];
    }

    // ------------------------------------------- emergency voting (Exp 3)

    function setGuardians(address[] calldata list) external {
        require(list.length > 0 && list.length <= MAX_GUARDIANS, "1-5 guardians");
        address[] storage old = guardians[msg.sender];
        for (uint256 i = 0; i < old.length; i++) {
            isGuardianOf[msg.sender][old[i]] = false;
        }
        delete guardians[msg.sender];
        for (uint256 i = 0; i < list.length; i++) {
            address g = list[i];
            require(g != address(0) && g != msg.sender && !isGuardianOf[msg.sender][g], "Bad guardian");
            isGuardianOf[msg.sender][g] = true;
            guardians[msg.sender].push(g);
        }
        emit GuardiansSet(msg.sender, list.length);
    }

    function getGuardians(address patient) external view returns (address[] memory) {
        return guardians[patient];
    }

    function requestEmergency(uint256 id) external onlyDoctor validRecord(id) returns (uint256) {
        require(guardians[records[id].patient].length > 0, "No guardians");
        emergencies.push(
            EmergencyRequest(msg.sender, id, 0, block.timestamp + EMERGENCY_VOTE_WINDOW, false)
        );
        uint256 requestId = emergencies.length - 1;
        emit EmergencyRequested(requestId, id, msg.sender);
        return requestId;
    }

    /// @notice One vote per guardian, only while the window is open. Majority grants access.
    function voteEmergency(uint256 requestId) external {
        require(requestId < emergencies.length, "Invalid request");
        EmergencyRequest storage r = emergencies[requestId];
        address patient = records[r.recordId].patient;
        require(isGuardianOf[patient][msg.sender], "Not a guardian");
        require(!hasVoted[requestId][msg.sender], "Already voted");
        require(block.timestamp <= r.deadline, "Voting closed");
        require(!r.granted, "Already granted");

        hasVoted[requestId][msg.sender] = true;
        r.votes += 1;
        emit EmergencyVote(requestId, msg.sender, r.votes);

        if (r.votes * 2 > guardians[patient].length) {
            r.granted = true;
            _grant(r.recordId, r.doctor, EMERGENCY_ACCESS_DURATION);
            emit EmergencyGranted(requestId, r.recordId, r.doctor, access[r.recordId][r.doctor]);
        }
    }

    function getEmergency(uint256 requestId)
        external
        view
        returns (address doctor, uint256 recordId, uint256 votes, uint256 deadline, bool granted)
    {
        require(requestId < emergencies.length, "Invalid request");
        EmergencyRequest storage r = emergencies[requestId];
        return (r.doctor, r.recordId, r.votes, r.deadline, r.granted);
    }

    function emergencyCount() external view returns (uint256) {
        return emergencies.length;
    }
}
