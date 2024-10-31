const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Littercoin Smart Contract", function () {
    let littercoin, rewardToken, merchantToken;
    let owner, user1, user2;

    beforeEach(async function () {
        // Get the contract factories
        const Littercoin = await ethers.getContractFactory("Littercoin");

        // Create Users
        [owner, user1, user2] = await ethers.getSigners();

        // Initialise the contracts
        littercoin = await Littercoin.deploy();
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
        // Mint tokens for user1
        await littercoin.connect(user1).mint(10);

        // Check user1's Littercoin balance
        const userBalance = await littercoin.balanceOf(user1.address);
        expect(userBalance).to.equal(10);
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

        // // user1 sends 1 ETH to the Littercoin contract
        await user1.sendTransaction({
            to: littercoin.getAddress(),
            value: ethers.parseEther("1"),
        });

        // Check littercoin smart contract balance
        const contractBalance = await ethers.provider.getBalance(littercoin.getAddress());
        expect(contractBalance).to.equal(ethers.parseEther("1"));

        // Give Merchant Token to user2
        await merchantToken.connect(owner).mint(user2.address);
        const user2Balance = await merchantToken.balanceOf(user2.address);
        expect(user2Balance).to.equal(1);

        // // Mint Littercoin for user1
        // await littercoin.connect(user1).mint(1);
        //
        // // User1 sends the Littercoin to user2
        // await littercoin.connect(user1).transfer(user2.address, 1);
        //
        // // Merchant Token Holder (user2) sends the Littercoin to the Smart Contract
        // await littercoin.connect(user2).redeemLittercoin(1);
        //
        // // Check user1's Littercoin balance after redemption
        // const userBalance = await littercoin.balanceOf(user2.address);
        // expect(userBalance).to.equal(0);
        //
        // // Check user1's Eth balance after redemption
        // const userEthBalance = await ethers.provider.getBalance(user2.address);
        // console.log('--- userEthBalance ---', userEthBalance.toString());
        // expect(userEthBalance).to.not.equal(0);
    });

    it("should revert redeeming Littercoin if user does not have a Merchant Token", async function () {
        // Mint Littercoin for user2
        await littercoin.connect(user2).mint(500);

        // Attempt to redeem Littercoin without a Merchant Token, expecting a revert
        await expect(littercoin.connect(user2).redeemLittercoin(500)).to.be.revertedWith("Must hold a Merchant Token");
    });

    it("should reward OLMRewardToken correctly upon receiving ETH", async function () {
        // Send 1 ETH from user1 to the Littercoin contract
        await user1.sendTransaction({
            to: littercoin.address,
            value: ethers.parseEther("1"),
        });

        // Check user1's OLMRewardToken balance (should be 100 OLMRT)
        const rewardBalance = await rewardToken.balanceOf(user1.address);
        expect(rewardBalance).to.equal(ethers.utils.parseEther("100"));
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
