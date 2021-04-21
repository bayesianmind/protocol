const hre = require("hardhat");
const ethers = hre.ethers;

const deployPickleToken = async () => {
  console.log("deploying pickle token...");

  const childChainManager = "0x195fe6EE6639665CCeB15BCCeB9980FC445DFa0B";
  const minter = "0xaCfE4511CE883C14c4eA40563F176C3C09b4c47C";

  const PickleTokenFactory = await ethers.getContractFactory(
    "src/polygon/pickle-token.sol:PickleToken"
  );
  const PickleToken = await PickleTokenFactory.deploy(
    "PickleToken",
    "PICKLE",
    18,
    childChainManager,
    minter
  );
  console.log("pickle token deployed at ", PickleToken.address);
};

const deployMasterChef = async () => {
  console.log("deploying master chef...");

  const pickle = "0x835804CC589E07FBbbCE7B8c830F219Dac407F63";
  const devaddr = "0xaCfE4511CE883C14c4eA40563F176C3C09b4c47C";
  const picklePerBlock = 1000000000000;
  const startBlock = 13560000;
  const bonusEndBlock = 0;

  const MasterChefFactory = await ethers.getContractFactory(
    "src/polygon/masterchef.sol:MasterChef"
  );
  const MasterChef = await MasterChefFactory.deploy(
    pickle,
    devaddr,
    picklePerBlock,
    startBlock,
    bonusEndBlock
  );
  console.log("master chef deployed at ", MasterChef.address);
};

const handOverPermsToMasterChef = async () => {
  console.log("grant mint role to master chef...");

  const pickle = "0x835804CC589E07FBbbCE7B8c830F219Dac407F63";
  const masterchef = "0x52076435D07DDa4c43dD87E76B624c5D0ce4B01D";
  const DEFAULT_ADMIN_ROLE =
    "0x0000000000000000000000000000000000000000000000000000000000000000";

  const pickleToken = await ethers.getContractAt(
    "src/polygon/pickle-token.sol:PickleToken",
    pickle
  );
  const prevAdmin = new ethers.Wallet(
    "prevAdmin's privatekey here", // 0xaCfE4511CE883C14c4eA40563F176C3C09b4c47C = minter at PickleToken contract deployment.
    ethers.provider
  );
  await pickleToken
    .connect(prevAdmin)
    .grantRole(DEFAULT_ADMIN_ROLE, masterchef);

  console.log("mint role granted!");
};

const main = async () => {
  // await deployPickleToken();
  // await deployMasterChef();
  await handOverPermsToMasterChef();
};

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });