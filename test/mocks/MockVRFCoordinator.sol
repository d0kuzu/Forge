// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IVRFCoordinatorV2Plus} from "../../src/chainlink/IVRFCoordinatorV2Plus.sol";
import {VRFV2PlusClient} from "../../src/chainlink/VRFV2PlusClient.sol";

/// @title MockVRFCoordinator — Test mock for Chainlink VRF v2.5 Coordinator
/// @notice Simulates VRF behavior for Foundry unit tests.
///         Allows manual fulfillment of random words requests.
contract MockVRFCoordinator is IVRFCoordinatorV2Plus {
    /// @notice Counter for generating unique request IDs
    uint256 private _nextRequestId = 1;

    /// @notice Stored request data for later fulfillment
    struct PendingRequest {
        address consumer;    // The contract that made the request
        uint32 numWords;     // Number of random words requested
        bool exists;
    }

    /// @notice Mapping of request ID => pending request
    mapping(uint256 => PendingRequest) public pendingRequests;

    /// @notice All request IDs in order
    uint256[] public requestIds;

    // ============================================================
    //                         EVENTS
    // ============================================================

    event RandomWordsRequested(
        uint256 indexed requestId,
        address indexed consumer,
        uint256 subId,
        uint32 callbackGasLimit,
        uint32 numWords
    );

    event RandomWordsFulfilled(
        uint256 indexed requestId,
        address indexed consumer,
        uint256[] randomWords
    );

    // ============================================================
    //                    VRF COORDINATOR API
    // ============================================================

    /// @notice Simulate receiving a VRF request
    /// @dev Stores the request for later manual fulfillment
    function requestRandomWords(
        VRFV2PlusClient.RandomWordsRequest calldata req
    ) external override returns (uint256 requestId) {
        requestId = _nextRequestId++;

        pendingRequests[requestId] = PendingRequest({
            consumer: msg.sender,
            numWords: req.numWords,
            exists: true
        });

        requestIds.push(requestId);

        emit RandomWordsRequested(
            requestId,
            msg.sender,
            req.subId,
            req.callbackGasLimit,
            req.numWords
        );
    }

    // ============================================================
    //                    TEST HELPERS
    // ============================================================

    /// @notice Manually fulfill a VRF request with specific random words
    /// @dev Calls rawFulfillRandomWords on the consumer contract
    /// @param requestId    The request to fulfill
    /// @param randomWords  The "random" values to provide
    function fulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) external {
        PendingRequest storage req = pendingRequests[requestId];
        require(req.exists, "MockVRF: request not found");
        require(randomWords.length == req.numWords, "MockVRF: wrong numWords");

        address consumer = req.consumer;
        delete pendingRequests[requestId];

        // Call the consumer's rawFulfillRandomWords
        (bool success, bytes memory data) = consumer.call(
            abi.encodeWithSignature(
                "rawFulfillRandomWords(uint256,uint256[])",
                requestId,
                randomWords
            )
        );

        if (!success) {
            // Bubble up revert reason
            if (data.length > 0) {
                assembly {
                    revert(add(data, 32), mload(data))
                }
            }
            revert("MockVRF: fulfillment failed");
        }

        emit RandomWordsFulfilled(requestId, consumer, randomWords);
    }

    /// @notice Fulfill with a deterministic "random" value derived from requestId
    /// @dev Convenience method for simple tests
    function fulfillRandomWordsSimple(uint256 requestId) external {
        PendingRequest storage req = pendingRequests[requestId];
        require(req.exists, "MockVRF: request not found");

        uint256[] memory randomWords = new uint256[](req.numWords);
        for (uint32 i = 0; i < req.numWords; i++) {
            randomWords[i] = uint256(keccak256(abi.encodePacked(requestId, i, block.timestamp)));
        }

        address consumer = req.consumer;
        delete pendingRequests[requestId];

        (bool success, bytes memory data) = consumer.call(
            abi.encodeWithSignature(
                "rawFulfillRandomWords(uint256,uint256[])",
                requestId,
                randomWords
            )
        );

        if (!success) {
            if (data.length > 0) {
                assembly {
                    revert(add(data, 32), mload(data))
                }
            }
            revert("MockVRF: fulfillment failed");
        }

        emit RandomWordsFulfilled(requestId, consumer, randomWords);
    }

    // ============================================================
    //                      VIEW HELPERS
    // ============================================================

    /// @notice Get the number of pending requests
    function getPendingRequestCount() external view returns (uint256) {
        uint256 count = 0;
        for (uint256 i = 0; i < requestIds.length; i++) {
            if (pendingRequests[requestIds[i]].exists) count++;
        }
        return count;
    }

    /// @notice Get the latest request ID
    function getLatestRequestId() external view returns (uint256) {
        require(requestIds.length > 0, "MockVRF: no requests");
        return requestIds[requestIds.length - 1];
    }

    /// @notice Get total request count (including fulfilled)
    function getTotalRequestCount() external view returns (uint256) {
        return requestIds.length;
    }
}
