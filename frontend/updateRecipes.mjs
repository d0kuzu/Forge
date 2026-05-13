import { createWalletClient, createPublicClient, http, parseAbi, parseEther } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { localhost } from 'viem/chains';

const account = privateKeyToAccount('0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80');
const client = createWalletClient({ account, chain: localhost, transport: http('http://127.0.0.1:8545') });
const publicClient = createPublicClient({ chain: localhost, transport: http('http://127.0.0.1:8545') });

const itemsAddress = '0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512';
const itemsAbi = parseAbi([
  'function addCraftRecipe(uint256 resultItemId, uint256[] calldata inputItemIds, uint256[] calldata inputAmounts, uint256 dustCost, uint256 forgeCoinCost) external returns (uint256 recipeId)',
  'function updateCraftRecipe(uint256 recipeId, uint256[] calldata inputItemIds, uint256[] calldata inputAmounts, uint256 dustCost, uint256 forgeCoinCost) external',
  'function defineItem(uint256 itemId, string name, uint8 rarity, uint256 maxSupply, bool craftable) external'
]);

async function run() {
  console.log("Fixing Recipe 0 (Shield + Dust -> Upgraded Shield)...");
  let req = await publicClient.simulateContract({
    address: itemsAddress,
    abi: itemsAbi,
    functionName: 'updateCraftRecipe',
    args: [0n, [2n], [1n], parseEther('100'), 0n], // 1 Shield (ID 2), 100 Dust -> Upgraded Shield
    account
  });
  await client.writeContract(req.request);

  console.log("Defining Upgraded Sword...");
  try {
     req = await publicClient.simulateContract({
      address: itemsAddress,
      abi: itemsAbi,
      functionName: 'defineItem',
      args: [4n, "Upgraded Sword", 1, 0n, true], // Rarity 1, craftable true
      account
    });
    await client.writeContract(req.request);
  } catch(e) { console.log("Item already defined or error:", e.shortMessage || e.message) }

  console.log("Adding Recipe 1 (Sword + Dust -> Upgraded Sword)...");
  try {
    req = await publicClient.simulateContract({
      address: itemsAddress,
      abi: itemsAbi,
      functionName: 'addCraftRecipe',
      args: [4n, [1n], [1n], parseEther('100'), 0n], // 1 Sword (ID 1), 100 Dust -> Upgraded Sword (ID 4)
      account
    });
    const hash = await client.writeContract(req.request);
    console.log(`Recipe Added! Tx: ${hash}`);
  } catch(e) { console.log("Recipe error:", e.shortMessage || e.message) }
}

run().catch(console.error);
