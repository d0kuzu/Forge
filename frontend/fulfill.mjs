import { createWalletClient, createPublicClient, http, parseAbi } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { localhost } from 'viem/chains';

const account = privateKeyToAccount('0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80');
const client = createWalletClient({ account, chain: localhost, transport: http('http://127.0.0.1:8545') });
const publicClient = createPublicClient({ chain: localhost, transport: http('http://127.0.0.1:8545') });

const vrfAddress = '0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0';
const gachaAddress = '0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9';
const abi = parseAbi(['function fulfillRandomWordsSimple(uint256 requestId)']);

async function fulfill() {
  console.log("Fulfilling VRF Requests...");
  for (let i = 1; i <= 5; i++) {
    try {
      const { request } = await publicClient.simulateContract({
        address: vrfAddress,
        abi,
        functionName: 'fulfillRandomWordsSimple',
        args: [BigInt(i)],
        account
      });
      const hash = await client.writeContract(request);
      console.log(`Fulfilled request ${i}: ${hash}`);
    } catch (e) {
      console.log(`Failed request ${i}:`, e.shortMessage || e.message);
    }
  }
  console.log("Done!");
}
fulfill();
