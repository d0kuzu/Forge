// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IVRFCoordinatorV2Plus} from "./IVRFCoordinatorV2Plus.sol";

/// @title VRFConsumerBaseV2Plus — Abstract base for VRF v2.5 consumers
/// @notice Upgradeable-compatible VRF consumer base (no constructor dependency)
/// @dev Unlike the official Chainlink version, this base stores the coordinator
///      in a storage variable instead of immutable, making it compatible with
///      proxy patterns (UUPS/Transparent).
abstract contract VRFConsumerBaseV2Plus {
    /// @notice VRF Coordinator contract reference
    /// @dev Stored in regular storage for proxy compatibility.
    ///      Set via _setVRFCoordinator() in the initializer.
    IVRFCoordinatorV2Plus internal s_vrfCoordinator;

    /// @notice Only the VRF Coordinator can call fulfillRandomWords
    error OnlyCoordinatorCanFulfill(address have, address want);

    /// @notice VRF Coordinator address has not been set
    error VRFCoordinatorNotSet();

    /// @notice Set the VRF Coordinator address
    /// @dev Call this in the initializer of the upgradeable contract
    function _setVRFCoordinator(address coordinator) internal {
        s_vrfCoordinator = IVRFCoordinatorV2Plus(coordinator);
    }

    /// @notice Called by VRFCoordinator when random words are ready
    /// @dev Must be implemented by the consuming contract
    /// @param requestId    The VRF request ID
    /// @param randomWords  Array of random values
    function rawFulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) external {
        if (msg.sender != address(s_vrfCoordinator)) {
            revert OnlyCoordinatorCanFulfill(msg.sender, address(s_vrfCoordinator));
        }
        fulfillRandomWords(requestId, randomWords);
    }

    /// @notice Override this function to handle VRF responses
    /// @param requestId    The VRF request ID
    /// @param randomWords  Array of random values
    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal virtual;
}
