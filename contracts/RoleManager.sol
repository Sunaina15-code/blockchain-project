// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title RoleManager
/// @notice Base contract "A" (Exp 2 - inheritance): admin + doctor roles.
abstract contract RoleManager {
    address public admin;
    mapping(address => bool) public isDoctor;

    event DoctorRegistered(address indexed doctor);
    event DoctorRemoved(address indexed doctor);

    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin");
        _;
    }

    modifier onlyDoctor() {
        require(isDoctor[msg.sender], "Only doctor");
        _;
    }

    constructor() {
        admin = msg.sender;
    }

    function registerDoctor(address doctor) external onlyAdmin {
        require(doctor != address(0), "Zero address");
        isDoctor[doctor] = true;
        emit DoctorRegistered(doctor);
    }

    function removeDoctor(address doctor) external onlyAdmin {
        isDoctor[doctor] = false;
        emit DoctorRemoved(doctor);
    }
}
