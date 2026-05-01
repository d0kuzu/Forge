// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {VRFV2PlusClient} from "./VRFV2PlusClient.sol";

/// @title IVRFCoordinatorV2Plus — Chainlink VRF Coordinator v2.5 interface
/// @notice Minimal interface matching the official Chainlink VRF v2.5 Coordinator
interface IVRFCoordinatorV2Plus {
    /// @notice Request random words from the VRF coordinator
    /// @param req  The random words request parameters
    /// @return requestId  The unique ID for this VRF request
    function requestRandomWords(
        VRFV2PlusClient.RandomWordsRequest calldata req
    ) external returns (uint256 requestId);
}
