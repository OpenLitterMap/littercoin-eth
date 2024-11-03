const { expect } = require("chai");
const { ethers } = require("hardhat");

async function main() {
    const DECIMALS = 8;
    const INITIAL_PRICE = ethers.parseUnits("2000", DECIMALS); // $2000

    const MockV3Aggregator = await ethers.getContractFactory("MockV3Aggregator");
    const mockV3Aggregator = await MockV3Aggregator.deploy(DECIMALS, INITIAL_PRICE);
    await mockV3Aggregator.deployed();
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});

describe("Littercoin Smart Contract", function () {
    let littercoin, rewardToken, merchantToken;
    let owner, user1, user2, user3;

    let mockV3Aggregator;
    let decimals = 8;
    let initialPrice = ethers.parseUnits("2000", decimals);

    beforeEach(async function () {

        const MockV3Aggregator = await ethers.getContractFactory("MockV3Aggregator");
        mockV3Aggregator = await MockV3Aggregator.deploy(decimals, initialPrice);
        await mockV3Aggregator.deployed();

        // Get the contract factories
        const Littercoin = await ethers.getContractFactory("Littercoin");

        // Create Users
        [owner, user1, user2, user3] = await ethers.getSigners();

        // Initialise the contracts
        littercoin = await Littercoin.deploy(mockV3Aggregator.getAddress());
        await littercoin.waitForDeployment();

        // Retrieve token addresses from the Littercoin contract
        const rewardTokenAddress = await littercoin.getRewardTokenAddress();
        const merchantTokenAddress = await littercoin.getMerchantTokenAddress();

        // Attach to the deployed token contracts
        rewardToken = await ethers.getContractAt("OLMRewardToken", rewardTokenAddress);
        merchantToken = await ethers.getContractAt("MerchantToken", merchantTokenAddress);
    });

    // Create Littercoin
    it("should mint Littercoin tokens correctly", async function () {

        // Sign a valid mint request off-chain
        const amount = 10;
        const nonce = 1;
        const messageHash = ethers.solidityPackedKeccak256(
            ["address", "uint256", "uint256"],
            [user1.address, amount, nonce]
        );
        const signature = await owner.signMessage(ethers.getBytes(messageHash));

        // Mint tokens for user1
        await expect(littercoin.connect(user1).mint(amount, nonce, signature))
            .to.emit(littercoin, "Mint")
            .withArgs(user1.address, amount);

        // Check user1's Littercoin balance
        const userBalance = await littercoin.balanceOf(user1.address);
        expect(userBalance).to.equal(amount);
    });

    // Create Littercoin - validation 1
    it("should not mint Littercoin if the amount is zero", async function () {
        // Attempt to mint zero tokens, expecting a revert
        await expect(littercoin.connect(user1).mint(0)).to.be.revertedWith("Amount must be greater than zero");
    });

    // Create Merchant Token
    it("should mint Merchant Token tokens correctly", async function () {
        // The owner can mint a Merchant Token for user2.
        await merchantToken.connect(owner).mint(user2.address);

        // Check user2s Merchant Token balance
        const user2Balance = await merchantToken.balanceOf(user2.address);
        expect(user2Balance).to.equal(1);
    });

    // Merchant Token Holder can send Littercoin to the Smart Contract and get Eth out
    it("should allow only users with Merchant Token to redeem Littercoin", async function () {
        // user1 sends 1 ETH to the Littercoin contract
        await user1.sendTransaction({
            to: littercoin.getAddress(),
            value: ethers.parseEther("1"),
        });

        // Check littercoin smart contract balance
        const contractBalance = await ethers.provider.getBalance(littercoin.getAddress());
        expect(contractBalance).to.equal(ethers.parseEther("1"));

        // Mint Merchant Token for user2
        await merchantToken.connect(owner).mint(user2.address);
        const user2Balance = await merchantToken.balanceOf(user2.address);
        expect(user2Balance).to.equal(1);

        // Mint Littercoin for user3
        await littercoin.connect(user3).mint(1);
        const user3Balance = await littercoin.balanceOf(user3.address);
        expect(user3Balance).to.equal(1);

        // User3 sends the Littercoin to the Merchant Token Holder (user2)
        await littercoin.connect(user3).transfer(user2.address, 1);
        const user3BalanceZero = await littercoin.balanceOf(user3.address);
        expect(user3BalanceZero).to.equal(0);

        const user2LittercoinBalance = await littercoin.balanceOf(user2.address);
        expect(user2LittercoinBalance).to.equal(1);

        // Merchant Token Holder (user2) sends the Littercoin to the Smart Contract
        // They should receive 1 ETH in return
        // and have 0 littercoin
        await littercoin.connect(user2).redeemLittercoin(1);

        // Check user2 Littercoin balance after redemption
        const user2LittercoinBalance_a = await littercoin.balanceOf(user2.address);
        expect(user2LittercoinBalance_a).to.equal(0);

        // Check user2's Eth balance after redemption
        const userEthBalance = await ethers.provider.getBalance(user2.address);
        expect(userEthBalance).to.not.equal(0); // 9999999916567839982327

        // User2 should still have the Merchant Token
        const user2MerchantTokenBalance = await merchantToken.balanceOf(user2.address);
        expect(user2MerchantTokenBalance).to.equal(1);
    });

    it("should revert redeeming Littercoin if user does not have a Merchant Token", async function () {
        // Mint Littercoin for user2
        await littercoin.connect(user2).mint(500);

        // Attempt to redeem Littercoin without a Merchant Token, expecting a revert
        await expect(littercoin.connect(user2).redeemLittercoin(500)).to.be.revertedWith("Must hold a Merchant Token");
    });

    it("should reward OLMRewardToken correctly upon receiving ETH", async function () {
        // Send 1 ETH from user1 to the Littercoin contract
        // We assume that 1 eth = $2000 for testing
        await user1.sendTransaction({
            to: littercoin.getAddress(),
            value: ethers.parseEther("1"),
        });

        // Check user1's OLMRewardToken balance (should be 2000 OLMRT)
        const rewardBalance = await rewardToken.balanceOf(user1.address);
        expect(rewardBalance).to.equal(2000);
    });

    it("should revert redeeming Littercoin if contract has insufficient ETH", async function () {
        // Mint Merchant Token to user1
        await merchantToken.connect(owner).mint(user1.address);

        // Mint Littercoin for user1
        await littercoin.connect(user1).mint(500);

        // Attempt to redeem Littercoin without sufficient ETH, expecting a revert
        await expect(littercoin.connect(user1).redeemLittercoin(500)).to.be.revertedWith("Not enough ETH in contract");
    });
});
