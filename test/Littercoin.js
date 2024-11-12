const { expect } = require("chai");
const { ethers, network} = require("hardhat");

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
    const merchantTokenExpiry = Math.floor(Date.now() / 1000) + (30 * 24 * 60 * 60); // 30 days from now

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
        const nonce = 1;
        const amount = 10;
        const expiry = Math.floor(Date.now() / 1000) + 3600; // 1 hour from now
        const signature = getMintSignature(owner, user1.address, amount, nonce, expiry);

        // Mint tokens for user1
        await expect(littercoin.connect(user1).mint(amount, nonce, expiry, signature))
            .to.emit(littercoin, "Mint")
            .withArgs(user1.address, amount);

        // Check user1's Littercoin balance
        const userBalance = await littercoin.balanceOf(user1.address);
        expect(userBalance).to.equal(amount);
    });

    it("should not allow non-owner to mint Merchant Tokens", async function () {
        await expect(merchantToken.connect(user1).mint(user2.address, merchantTokenExpiry))
            .to.be.revertedWith("Ownable: caller is not the owner");
    });

    // Create Littercoin - validation 1
    it("should not mint Littercoin if the amount is zero", async function () {
        const amount = 0;
        const nonce = 2;
        const expiry = Math.floor(Date.now() / 1000) + 3600;
        const signature = getMintSignature(owner, user1.address, amount, nonce, expiry);

        await expect(littercoin.connect(user1).mint(amount, nonce, expiry, signature))
            .to.be.revertedWith("Amount must be greater than zero");
    });

    // Create Merchant Token
    it("should mint Merchant Token tokens correctly", async function () {
        // The owner can mint a Merchant Token for user2.
        await merchantToken.connect(owner).mint(user2.address, merchantTokenExpiry);

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
        await merchantToken.connect(owner).mint(user2.address, merchantTokenExpiry);
        const user2Balance = await merchantToken.balanceOf(user2.address);
        expect(user2Balance).to.equal(1);

        // Mint Littercoin for user3
        const nonce = 3;
        const amount = 1;
        const expiry = Math.floor(Date.now() / 1000) + 3600;
        const signature = getMintSignature(owner, user3.address, amount, nonce, expiry);
        await littercoin.connect(user3).mint(amount, nonce, expiry, signature);
        const user3Balance = await littercoin.balanceOf(user3.address);
        expect(user3Balance).to.equal(1);

        // User3 sends the Littercoin to the Merchant Token Holder (user2)
        await littercoin.connect(user3)["safeTransferFrom(address,address,uint256)"](user3.address, user2.address, 1);
        const user3BalanceZero = await littercoin.balanceOf(user3.address);
        expect(user3BalanceZero).to.equal(0);

        const user2LittercoinBalance = await littercoin.balanceOf(user2.address);
        expect(user2LittercoinBalance).to.equal(1);

        // Merchant Token Holder (user2) sends the Littercoin to the Smart Contract
        // They should receive 1 ETH in return
        // and have 0 littercoin
        await littercoin.connect(user2).burnLittercoin([1], { gasLimit: 100000 });

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
        const nonce = 4;
        const amount = 1;
        const expiry = Math.floor(Date.now() / 1000) + 3600;
        const signature = getMintSignature(owner, user2.address, amount, nonce, expiry);
        await littercoin.connect(user2).mint(amount, nonce, expiry, signature);

        // Attempt to redeem Littercoin without a Merchant Token, expecting a revert
        await expect(littercoin.connect(user2).burnLittercoin([1], { gasLimit: 5000000 }))
            .to.be.revertedWith("Must hold a valid Merchant Token.");
    });

    it("should reward OLMRewardToken correctly upon receiving ETH", async function () {
        // Send 1 ETH from user1 to the Littercoin contract
        // We assume that 1 eth = $2000 for testing
        await user1.sendTransaction({
            to: littercoin.getAddress(),
            value: ethers.parseEther("1"),
        });

        // Check user1's OLMRewardToken balance ($2000 eth => 2000 OLMRewardTokens)
        const rewardBalance = await rewardToken.balanceOf(user1.address);
        expect(rewardBalance).to.equal(2000);
    });

    it("should revert redeeming Littercoin if contract has insufficient ETH", async function () {
        // Mint Merchant Token to user1
        await merchantToken.connect(owner).mint(user1.address, merchantTokenExpiry);

        // Mint Littercoin for user1
        const nonce = 5;
        const amount = 1;
        const expiry = Math.floor(Date.now() / 1000) + 3600;
        const signature = getMintSignature(owner, user1.address, amount, nonce, expiry);
        await littercoin.connect(user1).mint(amount, nonce, expiry, signature);

        // Attempt to redeem Littercoin without sufficient ETH, expecting a revert
        await expect(littercoin.connect(user1).burnLittercoin([1], { gasLimit: 1000000 }))
            .to.be.revertedWith("Not enough ETH in contract.");
    });

    it("should not mint a merchant token for a date in the past", async function () {
        // Mint Merchant Token for user2 with an expiration timestamp in the past
        const expiredTimestamp = Math.floor(Date.now() / 1000) - (60 * 60); // 1 hour ago

        await expect(merchantToken.connect(owner).mint(user2.address, expiredTimestamp))
            .to.be.revertedWith("Expiration must be in the future.");
    });

    it("should not allow redemption with an expired Merchant Token", async function () {
        // Get the current block timestamp
        const currentBlock = await ethers.provider.getBlock('latest');
        const currentTimestamp = currentBlock.timestamp;

        // Set Merchant Token expiry to 1 hour from now using blockchain time
        const merchantTokenExpiry = currentTimestamp + 3600; // 1 hour from now

        // Mint the merchant token
        await merchantToken.connect(owner).mint(user2.address, merchantTokenExpiry);

        // Mint Littercoin for user2
        const nonce = 6;
        const amount = 1;
        const expiry = Math.floor(Date.now() / 1000) + 3600; // 1 hour from now
        const signature = await getMintSignature(owner, user2.address, amount, nonce, expiry);
        await littercoin.connect(user2).mint(amount, nonce, expiry, signature);

        // Fast forward time by 2 hours to expire the Merchant Token
        await ethers.provider.send("evm_increaseTime", [3 * 3600]); // Increase time by 3 hours
        await ethers.provider.send("evm_mine"); // Mine a new block to apply the time increase

        // Verify that the Merchant Token is expired
        const tokenId = await merchantToken.getTokenIdByOwner(user2.address);
        const isExpired = await merchantToken.isExpired(tokenId);
        expect(isExpired).to.equal(true);

        // Add eth to the contract
        await user1.sendTransaction({ to: littercoin.getAddress(), value: ethers.parseEther("1") });

        // Attempt to redeem Littercoin with the expired Merchant Token
        await expect(littercoin.connect(user2).burnLittercoin([1]))
            .to.be.revertedWith("Must hold a valid Merchant Token.");
    });

    // it("should update valid token status upon transferring Merchant Token", async function () {
    //     // Mint Merchant Token for user1
    //     await merchantToken.connect(owner).mint(user1.address, merchantTokenExpiry);
    //
    //     // Mint Littercoin for user1 and user2
    //     const nonce1 = 8;
    //     const amount = 1;
    //     const expiry = Math.floor(Date.now() / 1000) + 3600;
    //     const signature1 = await getMintSignature(owner, user1.address, amount, nonce1, expiry);
    //     await littercoin.connect(user1).mint(amount, nonce1, expiry, signature1);
    //
    //     const nonce2 = 9;
    //     const signature2 = await getMintSignature(owner, user2.address, amount, nonce2, expiry);
    //     await littercoin.connect(user2).mint(amount, nonce2, expiry, signature2);
    //
    //     // User1 redeems Littercoin successfully
    //     await user1.sendTransaction({ to: littercoin.getAddress(), value: ethers.parseEther("1") });
    //     await littercoin.connect(user1).burnLittercoin([1]);
    //
    //     // Transfer Merchant Token from user1 to user2
    //     await merchantToken.connect(user1).transferFrom(user1.address, user2.address, 1);
    //
    //     // User1 should no longer have a valid Merchant Token
    //     expect(await merchantToken.hasValidMerchantToken(user1.address)).to.equal(false);
    //
    //     // User1 cannot redeem Littercoin now
    //     await expect(littercoin.connect(user1).burnLittercoin([2]))
    //         .to.be.revertedWith("Must hold a valid Merchant Token.");
    //
    //     // User2 should now have a valid Merchant Token
    //     expect(await merchantToken.hasValidMerchantToken(user2.address)).to.equal(true);
    //
    //     // User2 can redeem Littercoin
    //     await littercoin.connect(user2).burnLittercoin([2]);
    // });

    /**
     * Helper function to get a signature for minting tokens.
     *
     * @param {Object} signer - The signer (owner) who will sign the message.
     * @param {string} userAddress - The address of the user for whom tokens will be minted.
     * @param {number} amount - The amount of tokens to mint.
     * @param {number} nonce - The unique nonce to ensure the signature is unique.
     * @param {number} expiry - The expiry time of the minting
     * @returns {Promise<string>} - The signature for the minting request.
     */
    async function getMintSignature (signer, userAddress, amount, nonce, expiry)
    {
        const messageHash = ethers.solidityPackedKeccak256(
            ["address", "uint256", "uint256", "uint256"],
            [userAddress, amount, nonce, expiry]
        );

        return await signer.signMessage(ethers.getBytes(messageHash));
    }
});
