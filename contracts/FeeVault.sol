// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title FeeVault
/// @notice Base contract "B" (Exp 2 + Exp 4): payable fees and a withdraw pattern,
///         like the vending machine / donation exercises.
abstract contract FeeVault {
    mapping(address => uint256) public consultationFee; // doctor => fee in wei
    mapping(address => uint256) public pendingBalance;  // doctor => withdrawable wei

    event FeeSet(address indexed doctor, uint256 fee);
    event FeePaid(address indexed patient, address indexed doctor, uint256 amount);
    event Withdrawn(address indexed doctor, uint256 amount);

    function _credit(address doctor) internal {
        pendingBalance[doctor] += msg.value;
    }

    /// @notice Doctor pulls their earned balance (state is cleared before sending).
    function withdraw() external {
        uint256 amount = pendingBalance[msg.sender];
        require(amount > 0, "Nothing to withdraw");
        pendingBalance[msg.sender] = 0;
        (bool ok, ) = payable(msg.sender).call{value: amount}("");
        require(ok, "Transfer failed");
        emit Withdrawn(msg.sender, amount);
    }
}
