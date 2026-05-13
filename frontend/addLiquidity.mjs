import { createWalletClient, createPublicClient, http, parseAbi, parseEther } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { localhost } from 'viem/chains';

const account = privateKeyToAccount('0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80');
const client = createWalletClient({ account, chain: localhost, transport: http('http://127.0.0.1:8545') });
const publicClient = createPublicClient({ chain: localhost, transport: http('http://127.0.0.1:8545') });

const coinAddress = '0x5FbDB2315678afecb367f032d93F642f64180aa3';
const itemsAddress = '0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512';
const ammAddress = '0x5FC8d32690cc91D4c39d9d3abcBD16989F875707';

const coinAbi = parseAbi(['function approve(address spender, uint256 amount)']);
const itemsAbi = parseAbi(['function setApprovalForAll(address operator, bool approved)']);
const ammAbi = parseAbi(['function addLiquidity(uint256 forgeCoinDesired, uint256 dustDesired, uint256 forgeCoinMin, uint256 dustMin, uint256 deadline)']);

async function addLiquidity() {
  console.log("Approving ForgeCoin...");
  let req = await publicClient.simulateContract({
    address: coinAddress,
    abi: coinAbi,
    functionName: 'approve',
    args: [ammAddress, parseEther('100000')],
    account
  });
  await client.writeContract(req.request);

  console.log("Approving ForgeItems...");
  req = await publicClient.simulateContract({
    address: itemsAddress,
    abi: itemsAbi,
    functionName: 'setApprovalForAll',
    args: [ammAddress, true],
    account
  });
  await client.writeContract(req.request);

  console.log("Adding Liquidity...");
  req = await publicClient.simulateContract({
    address: ammAddress,
    abi: ammAbi,
    functionName: 'addLiquidity',
    args: [parseEther('10000'), parseEther('10000'), 0n, 0n, BigInt(Math.floor(Date.now() / 1000) + 3600)],
    account
  });
  const hash = await client.writeContract(req.request);
  console.log(`Liquidity Added! Tx: ${hash}`);
}

addLiquidity().catch(console.error);
