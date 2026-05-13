// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {MockVRFCoordinator} from "../test/mocks/MockVRFCoordinator.sol";

contract FulfillScript is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));
        vm.startBroadcast(deployerPrivateKey);

        MockVRFCoordinator vrf = MockVRFCoordinator(0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0);
        address gacha = 0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9;

        // Fulfill requests 1 to 5 just in case
        for (uint256 i = 1; i <= 5; i++) {
            uint256[] memory words = new uint256[](1);
            words[0] = uint256(keccak256(abi.encodePacked(i, block.timestamp)));
            try vrf.fulfillRandomWords(i, words) {
                console2.log("Fulfilled request", i);
            } catch {
                // Ignore if request doesn't exist
            }
        }

        vm.stopBroadcast();
    }
}
