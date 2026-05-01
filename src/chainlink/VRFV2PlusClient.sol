// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title VRFV2PlusClient — Chainlink VRF v2.5 request parameter library
/// @notice Local minimal version matching the official Chainlink VRF v2.5 API
/// @dev Used by GachaLootbox to build VRF random number requests
library VRFV2PlusClient {
    /// @notice Parameters for requesting random words from VRF
    /// @param keyHash        Gas lane key hash
    /// @param subId          VRF subscription ID
    /// @param requestConfirmations  Number of block confirmations before callback
    /// @param callbackGasLimit      Gas limit for the fulfillRandomWords callback
    /// @param numWords       Number of random words to request
    /// @param extraArgs      ABI-encoded extra arguments (e.g. nativePayment flag)
    struct RandomWordsRequest {
        bytes32 keyHash;
        uint256 subId;
        uint16 requestConfirmations;
        uint32 callbackGasLimit;
        uint32 numWords;
        bytes extraArgs;
    }

    /// @notice Selector for extra args versioning
    bytes4 constant EXTRA_ARGS_V1_TAG = bytes4(keccak256("VRF ExtraArgsV1"));

    /// @notice Encode extra arguments for VRF v2.5
    /// @param nativePayment  Whether to pay for VRF in native token (true) or LINK (false)
    function _argsToBytes(bool nativePayment) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(EXTRA_ARGS_V1_TAG, nativePayment);
    }
}
