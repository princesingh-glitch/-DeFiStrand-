
const hre = require("hardhat");

async function main() {
  console.log("=".repeat(50));
  console.log("Deploying DeFiStrand Contract to Core Testnet 2");
  console.log("=".repeat(50));
  console.log();

  // Get the deployer's address
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying with account:", deployer.address);
  
  // Get account balance
  const balance = await hre.ethers.provider.getBalance(deployer.address);
  console.log("Account balance:", hre.ethers.formatEther(balance), "ETH");
  console.log();

  // Deploy the contract
  console.log("Deploying DeFiStrand contract...");
  const Project = await hre.ethers.getContractFactory("Project");
  const project = await Project.deploy();

  await project.waitForDeployment();

  const contractAddress = await project.getAddress();

  console.log("✅ DeFiStrand contract deployed successfully!");
  console.log();
  console.log("=".repeat(50));
  console.log("Deployment Summary");
  console.log("=".repeat(50));
  console.log("Contract Address:", contractAddress);
  console.log("Network:", "Core Testnet 2");
  console.log("Chain ID:", "1114");
  console.log("Deployer:", deployer.address);
  console.log("Block Number:", await hre.ethers.provider.getBlockNumber());
  console.log("Timestamp:", new Date().toISOString());
  console.log("=".repeat(50));
  console.log();

  console.log("Next Steps:");
  console.log("1. Save the contract address:", contractAddress);
  console.log("2. Verify contract (optional):");
  console.log(`   npx hardhat verify --network core_testnet ${contractAddress}`);
  console.log("3. Interact with the contract using the address above");
  console.log();

  // Display contract features
  console.log("=".repeat(50));
  console.log("Contract Features:");
  console.log("=".repeat(50));
  console.log("✓ Create DeFi Strands with custom risk levels");
  console.log("✓ Deposit funds and earn yield");
  console.log("✓ Claim accrued yield based on time and risk");
  console.log("✓ Add liquidity to pools");
  console.log("✓ Emergency withdrawal mechanism");
  console.log("✓ Pausable for emergency situations");
  console.log("=".repeat(50));
  console.log();

  // Save deployment info to a file
  const fs = require('fs');
  const deploymentInfo = {
    contractAddress: contractAddress,
    network: "Core Testnet 2",
    chainId: 1114,
    deployer: deployer.address,
    deploymentTime: new Date().toISOString(),
    blockNumber: await hre.ethers.provider.getBlockNumber()
  };

  fs.writeFileSync(
    'deployment-info.json',
    JSON.stringify(deploymentInfo, null, 2)
  );
  console.log("✅ Deployment info saved to deployment-info.json");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Deployment failed:");
    console.error(error);
    process.exit(1);
  });
