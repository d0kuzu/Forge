const fs = require('fs');
const path = require('path');

// 1. Copy deployments.json
try {
  fs.copyFileSync('deployments.json', 'frontend/src/config/deployments.json');
  console.log('✓ Copied deployments.json successfully!');
} catch (err) {
  console.error('Failed to copy deployments.json:', err.message);
}

// 2. Extract and copy ABIs
const contracts = [
  'ForgeAMM',
  'ForgeCoin',
  'ForgeGovernor',
  'ForgeItems',
  'ForgeTimelock',
  'ForgeVault',
  'GachaLootbox',
  'NFTRentalVault'
];

contracts.forEach((contract) => {
  const srcPath = path.join('out', `${contract}.sol`, `${contract}.json`);
  const destPath = path.join('frontend', 'src', 'config', 'abi', `${contract}.json`);

  try {
    if (fs.existsSync(srcPath)) {
      const data = JSON.parse(fs.readFileSync(srcPath, 'utf8'));
      const wrapper = { abi: data.abi };
      
      // Ensure target directory exists
      fs.mkdirSync(path.dirname(destPath), { recursive: true });
      
      fs.writeFileSync(destPath, JSON.stringify(wrapper, null, 2), 'utf8');
      console.log(`✓ Successfully extracted and saved ABI for ${contract}`);
    } else {
      console.warn(`⚠ Source file not found: ${srcPath}`);
    }
  } catch (err) {
    console.error(`Failed to process ${contract}:`, err.message);
  }
});
