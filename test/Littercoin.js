const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Littercoin Smart Contract", function () {
    let littercoin, rewardToken, merchantToken;
    let littercoinAddress;
    let owner, user1, user2, user3;

    let mockV3Aggregator;
    const decimals = 8;
    let initialPrice = ethers.parseUnits("2000", decimals);
    const merchantTokenExpiry = Math.floor(Date.now() / 1000) + (30 * 24 * 60 * 60); // 30 days from now

    beforeEach(async function () {

        // Create Users
        [owner, user1, user2, user3] = await ethers.getSigners();

        const MockV3Aggregator = await ethers.getContractFactory("MockV3Aggregator");
        mockV3Aggregator = await MockV3Aggregator.deploy(decimals, initialPrice);
        await mockV3Aggregator.waitForDeployment();

        // Get the contract factories
        const Littercoin = await ethers.getContractFactory("Littercoin");

        // Initialise the contracts
        littercoin = await Littercoin.deploy(mockV3Aggregator.getAddress());
        await littercoin.waitForDeployment();
        littercoinAddress = await littercoin.getAddress();

        // Retrieve token addresses from the Littercoin contract
        const rewardTokenAddress = await littercoin.getRewardTokenAddress();
        const merchantTokenAddress = await littercoin.getMerchantTokenAddress();

        // Attach to the deployed token contracts
        rewardToken = await ethers.getContractAt("OLMRewardToken", rewardTokenAddress);
        merchantToken = await ethers.getContractAt("MerchantToken", merchantTokenAddress);
    });

    /**
     * Littercoin Tests
     */

    it("should mint Littercoin tokens correctly", async function () {
        const nonce = 1;
        const amount = 10;
        const expiry = BigInt(Math.floor(Date.now() / 1000) + 3600); // 1 hour from now
        const signature = await getMintSignature(owner, littercoinAddress, user1.address, amount, nonce, expiry);

        // Call the mint function
        await expect(littercoin.connect(user1).mint(amount, nonce, expiry, signature))
            .to.emit(littercoin, "Mint")
            .withArgs(user1.address, amount);

        // Check user1's Littercoin balance
        const userBalance = await littercoin.balanceOf(user1.address);
        expect(userBalance).to.equal(amount);
    });

    it("should not mint Littercoin if the amount is zero", async function () {
        const amount = 0;
        const nonce = 2;
        const expiry = Math.floor(Date.now() / 1000) + 3600;
        const signature = await getMintSignature(owner, littercoinAddress, user1.address, amount, nonce, expiry);

        await expect(littercoin.connect(user1).mint(amount, nonce, expiry, signature))
            .to.be.revertedWith("Amount must be greater than zero and less than 10");
    });

    it("should not mint Littercoin if the amount is greater than 10", async function () {
        const amount = 11;
        const nonce = 3;
        const expiry = Math.floor(Date.now() / 1000) + 3600;
        const signature = await getMintSignature(owner, littercoinAddress, user1.address, amount, nonce, expiry);

        await expect(littercoin.connect(user1).mint(amount, nonce, expiry, signature))
            .to.be.revertedWith("Amount must be greater than zero and less than 10");
    });

    it("should not allow minting Littercoin with an invalid signature", async function () {
        const nonce = 7;
        const amount = 10;
        const expiry = (await ethers.provider.getBlock('latest')).timestamp + 3600;

        // Generate signature using user1 instead of the owner
        const invalidSignature = await getMintSignature(user1, littercoinAddress, user2.address, amount, nonce, expiry);

        await expect(littercoin.connect(user2).mint(amount, nonce, expiry, invalidSignature))
            .to.be.revertedWith("Invalid signature");
    });

    it("should not allow minting Littercoin with an expired signature", async function () {
        const nonce = 8;
        const amount = 10;
        const expiry = (await ethers.provider.getBlock('latest')).timestamp - 3600; // 1 hour ago

        const signature = await getMintSignature(owner, littercoinAddress, user2.address, amount, nonce, expiry);

        await expect(littercoin.connect(user2).mint(amount, nonce, expiry, signature))
            .to.be.revertedWith("Signature has expired");
    });

    it("should not allow minting Littercoin with a reused nonce", async function () {
        const nonce = 9;
        const amount = 10;
        const expiry = (await ethers.provider.getBlock('latest')).timestamp + 3600;

        const signature = await getMintSignature(owner, littercoinAddress, user2.address, amount, nonce, expiry);

        // First mint should succeed
        await littercoin.connect(user2).mint(amount, nonce, expiry, signature);

        // Second mint with the same nonce should fail
        await expect(littercoin.connect(user2).mint(amount, nonce, expiry, signature))
            .to.be.revertedWith("Nonce already used");
    });

    it("should not allow transferring Littercoin to zero address", async function () {
        const nonce = 14;
        const amount = 1;
        const expiry = (await ethers.provider.getBlock('latest')).timestamp + 3600;
        const signature = await getMintSignature(owner, littercoinAddress, user1.address, amount, nonce, expiry);
        await littercoin.connect(user1).mint(amount, nonce, expiry, signature);

        await expect(
            littercoin.connect(user1)["safeTransferFrom(address,address,uint256)"](user1.address, ethers.ZeroAddress, 1)
        ).to.be.revertedWith("ERC721: transfer to the zero address");
    });

    it("should update tokenTransferred to True Littercoin is transferred from user to merchant", async function () {
        // Mint Littercoin for user1
        const nonce = 11;
        const amount = 1;
        const expiry = Math.floor(Date.now() / 1000) + 3600;
        const signature = await getMintSignature(owner, littercoinAddress, user1.address, amount, nonce, expiry);
        await littercoin.connect(user1).mint(amount, nonce, expiry, signature);

        // Mint Merchant Token to user2
        await merchantToken.connect(owner).mint(user2.address, merchantTokenExpiry);

        // Transfer Littercoin from user1 to user2 (merchant)
        await littercoin.connect(user1).transferFrom(user1.address, user2.address, 1);

        // Get transferCount for tokenId 1
        const tokenTransferred = await littercoin.tokenTransferred(1);
        expect(tokenTransferred).to.equal(true);
    });

    it("should not allow Littercoin to be transferred more than once", async function () {
        const nonce = 13;
        const amount = 1;
        const expiry = Math.floor(Date.now() / 1000) + 3600;
        const signature = await getMintSignature(owner, littercoinAddress, user1.address, amount, nonce, expiry);
        await littercoin.connect(user1).mint(amount, nonce, expiry, signature);

        // Mint Merchant Token to user2
        await merchantToken.connect(owner).mint(user2.address, merchantTokenExpiry);

        // Transfer Littercoin from user1 to user2 (merchant)
        await littercoin.connect(user1).transferFrom(user1.address, user2.address, 1);

        // Attempt to transfer Littercoin from user2 to user3
        await expect(littercoin.connect(user2).transferFrom(user2.address, user3.address, 1))
            .to.be.revertedWith("Token has already been transferred");
    });

    it("should not allow Littercoin to be transferred to a non-merchant", async function () {
        const nonce = 14;
        const amount = 1;
        const expiry = Math.floor(Date.now() / 1000) + 3600;
        const signature = await getMintSignature(owner, littercoinAddress, user1.address, amount, nonce, expiry);
        await littercoin.connect(user1).mint(amount, nonce, expiry, signature);

        // Attempt to transfer Littercoin from user1 to user2 (who is not a merchant)
        await expect(littercoin.connect(user1).transferFrom(user1.address, user2.address, 1))
            .to.be.revertedWith("Recipient must be a valid merchant");
    });

    it("should not allow minting when the contract is paused", async function () {
        // Pause the contract
        await littercoin.connect(owner).pause();

        const nonce = 16;
        const amount = 1;
        const expiry = Math.floor(Date.now() / 1000) + 3600;
        const signature = await getMintSignature(owner, littercoinAddress, user1.address, amount, nonce, expiry);

        // Attempt to mint Littercoin
        await expect(littercoin.connect(user1).mint(amount, nonce, expiry, signature))
            .to.be.revertedWith("Pausable: paused");

        // Unpause the contract
        await littercoin.connect(owner).unpause();

        // Now minting should work
        await littercoin.connect(user1).mint(amount, nonce, expiry, signature);
    });

    it("should not allow transferring Littercoin when the contract is paused", async function () {
        const nonce = 17;
        const amount = 1;
        const expiry = Math.floor(Date.now() / 1000) + 3600;
        const signature = await getMintSignature(owner, littercoinAddress, user1.address, amount, nonce, expiry);
        await littercoin.connect(user1).mint(amount, nonce, expiry, signature);

        await merchantToken.connect(owner).mint(user2.address, merchantTokenExpiry);

        await littercoin.connect(owner).pause();

        // Attempt to transfer Littercoin from user1 to user2 (merchant)
        await expect(littercoin.connect(user1).transferFrom(user1.address, user2.address, 1))
            .to.be.revertedWith("Pausable: paused");

        await littercoin.connect(owner).unpause();

        // Now transfer should work
        await littercoin.connect(user1).transferFrom(user1.address, user2.address, 1);
    });

    it("should not allow burning Littercoin when the contract is paused", async function () {
        const nonce = 18;
        const amount = 1;
        const expiry = Math.floor(Date.now() / 1000) + 3600;
        const signature = await getMintSignature(owner, littercoinAddress, user1.address, amount, nonce, expiry);
        await littercoin.connect(user1).mint(amount, nonce, expiry, signature);
        await merchantToken.connect(owner).mint(user2.address, merchantTokenExpiry);

        // Send ETH to contract so burning can proceed
        await user1.sendTransaction({ to: littercoin.getAddress(), value: ethers.parseEther("1") });

        // Send littercoin from user 1 to user 2
        await littercoin.connect(user1).transferFrom(user1.address, user2.address, 1);

        // Pause the contract
        await littercoin.connect(owner).pause();

        // Attempt to burn Littercoin
        await expect(littercoin.connect(user2).burnLittercoin([1]))
            .to.be.revertedWith("Pausable: paused");

        // Unpause the contract
        await littercoin.connect(owner).unpause();

        // Now burning should work
        await littercoin.connect(user2).burnLittercoin([1]);
    });

    it("should not allow receiving ETH when the contract is paused", async function () {
        // Pause the contract
        await littercoin.connect(owner).pause();

        // Attempt to send ETH to the contract
        await expect(user1.sendTransaction({ to: littercoin.getAddress(), value: ethers.parseEther("1") }))
            .to.be.revertedWith("Pausable: paused");

        // Unpause the contract
        await littercoin.connect(owner).unpause();

        // Now sending ETH should work
        await user1.sendTransaction({ to: littercoin.getAddress(), value: ethers.parseEther("1") });
    });

    it("should not allow non-owner to pause or unpause the contract", async function () {
        // Attempt to pause the contract as non-owner
        await expect(littercoin.connect(user1).pause())
            .to.be.revertedWith("Ownable: caller is not the owner");

        // Pause the contract as owner
        await littercoin.connect(owner).pause();

        // Attempt to unpause the contract as non-owner
        await expect(littercoin.connect(user1).unpause())
            .to.be.revertedWith("Ownable: caller is not the owner");

        // Unpause the contract as owner
        await littercoin.connect(owner).unpause();
    });

    it("should not allow transferring Littercoin to zero address", async function () {
        const nonce = 14;
        const amount = 1;
        const expiry = Math.floor(Date.now() / 1000) + 3600;
        const signature = await getMintSignature(owner, littercoinAddress, user1.address, amount, nonce, expiry);
        await littercoin.connect(user1).mint(amount, nonce, expiry, signature);

        await expect(
            littercoin.connect(user1).transferFrom(user1.address, ethers.ZeroAddress, 1)
        ).to.be.revertedWith("ERC721: transfer to the zero address");
    });

    /**
     * Merchant Token Tests
     */

    // Create Merchant Token
    it("should mint Merchant Token tokens correctly", async function () {
        // The owner can mint a Merchant Token for user2.
        await merchantToken.connect(owner).mint(user2.address, merchantTokenExpiry);

        // Check user2s Merchant Token balance
        const user2Balance = await merchantToken.balanceOf(user2.address);
        expect(user2Balance).to.equal(1);
    });

    it("should not allow non-owner to mint Merchant Tokens", async function () {
        await expect(merchantToken.connect(user1).mint(user2.address, merchantTokenExpiry))
            .to.be.revertedWith("Ownable: caller is not the owner");
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
        const signature = await getMintSignature(owner, littercoinAddress, user3.address, amount, nonce, expiry);
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

    it("should not burn littercoin if no littercoin exists", async function () {

        // Mint Merchant Token for user2
        await merchantToken.connect(owner).mint(user2.address, merchantTokenExpiry);

        // Attempt to redeem Littercoin without a Merchant Token, expecting a revert
        await expect(littercoin.connect(user2).burnLittercoin([1], { gasLimit: 5000000 }))
            .to.be.revertedWith("No tokens in circulation.");

    });

    it("should revert redeeming Littercoin if user does not have a Merchant Token", async function () {
        // Mint Littercoin for user2
        const nonce = 4;
        const amount = 1;
        const expiry = Math.floor(Date.now() / 1000) + 3600;
        const signature = await getMintSignature(owner, littercoinAddress, user2.address, amount, nonce, expiry);
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
        // Mint Littercoin for user1
        const nonce = 5;
        const amount = 1;
        const expiry = Math.floor(Date.now() / 1000) + 3600;
        const signature = await getMintSignature(owner, littercoinAddress, user1.address, amount, nonce, expiry);
        await littercoin.connect(user1).mint(amount, nonce, expiry, signature);

        // Mint Merchant Token for user2
        await merchantToken.connect(owner).mint(user2.address, merchantTokenExpiry);

        // Send littercoin from user1 to user 2
        await littercoin.connect(user1)["safeTransferFrom(address,address,uint256)"](user1.address, user2.address, 1);

        // Attempt to redeem Littercoin without sufficient ETH, expecting a revert
        await expect(littercoin.connect(user2).burnLittercoin([1], { gasLimit: 1000000 }))
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

        // Mint Littercoin for user1
        const nonce = 6;
        const amount = 1;
        const expiry = Math.floor(Date.now() / 1000) + 3600; // 1 hour from now
        const signature = await getMintSignature(owner, littercoinAddress, user1.address, amount, nonce, expiry);
        await littercoin.connect(user1).mint(amount, nonce, expiry, signature);

        // Mint the merchant token for user2
        await merchantToken.connect(owner).mint(user2.address, merchantTokenExpiry);

        // Fast forward time by 2 hours to expire the Merchant Token
        await ethers.provider.send("evm_increaseTime", [3 * 3600]); // Increase time by 3 hours
        await ethers.provider.send("evm_mine"); // Mine a new block to apply the time increase

        const latestBlock = await ethers.provider.getBlock('latest');

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

    it("should allow owner to add expiration time to Merchant Token", async function () {
        const currentTimestamp = (await ethers.provider.getBlock('latest')).timestamp;
        const initialExpiry = currentTimestamp + 3600; // 1 hour from now

        // Mint Merchant Token to user1
        await merchantToken.connect(owner).mint(user1.address, initialExpiry);

        // Add 2 more hours to the expiration
        const additionalTime = 2 * 3600;
        await merchantToken.connect(owner).addExpirationTime(1, additionalTime);

        // Verify the new expiration timestamp
        const newExpiry = await merchantToken.getExpirationTimestamp(1);
        expect(newExpiry).to.equal(initialExpiry + additionalTime);
    });

    it("should not allow adding expiration time to a non-existent Merchant Token", async function () {
        const additionalTime = 3600;

        await expect(merchantToken.connect(owner).addExpirationTime(999, additionalTime))
            .to.be.revertedWith("Token does not exist");
    });

    it("should allow owner to invalidate a Merchant Token", async function () {
        const currentTimestamp = (await ethers.provider.getBlock('latest')).timestamp;
        const merchantTokenExpiry = currentTimestamp + 3600;

        // Mint Merchant Token to user1
        await merchantToken.connect(owner).mint(user1.address, merchantTokenExpiry);

        // Invalidate the Merchant Token
        await merchantToken.connect(owner).invalidateToken(1);

        // Verify that the token is now expired
        const isExpired = await merchantToken.isExpired(1);
        expect(isExpired).to.equal(true);

        // User1 should not be able to redeem Littercoin now
        await expect(littercoin.connect(user1).burnLittercoin([1]))
            .to.be.revertedWith("Must hold a valid Merchant Token.");
    });

    it("should not allow non-owner to invalidate a Merchant Token", async function () {
        const currentTimestamp = (await ethers.provider.getBlock('latest')).timestamp;
        const merchantTokenExpiry = currentTimestamp + 3600;

        // Mint Merchant Token to user1
        await merchantToken.connect(owner).mint(user1.address, merchantTokenExpiry);

        // Attempt to invalidate the token as user1
        await expect(merchantToken.connect(user1).invalidateToken(1))
            .to.be.revertedWith("Ownable: caller is not the owner");
    });

    it("should prevent users from transferring Merchant Tokens", async function () {
        // Mint Merchant Token to user1
        await merchantToken.connect(owner).mint(user1.address, merchantTokenExpiry);

        // Attempt to transfer the Merchant Token to user2
        await expect(merchantToken.connect(user1).transferFrom(user1.address, user2.address, 1))
            .to.be.revertedWith("Transfers are disabled");
    });

    it("should not allow adding zero additional expiration time", async function () {
        // Mint Merchant Token to user1
        await merchantToken.connect(owner).mint(user1.address, merchantTokenExpiry);

        // Attempt to add zero additional time
        await expect(merchantToken.connect(owner).addExpirationTime(1, 0))
            .to.be.revertedWith("Additional time must be greater than zero");
    });

    it("should allow retrieval of Merchant Token expiration timestamp", async function () {
        // Mint Merchant Token to user1
        await merchantToken.connect(owner).mint(user1.address, merchantTokenExpiry);

        // Retrieve the expiration timestamp
        const expiryTimestamp = await merchantToken.getExpirationTimestamp(1);
        expect(expiryTimestamp).to.equal(merchantTokenExpiry);
    });

    it("should not allow merchant token holders to mint Littercoin", async function () {
        // Mint Merchant Token for user1
        await merchantToken.connect(owner).mint(user1.address, merchantTokenExpiry);

        // Attempt to mint Littercoin for a Merchant Token Holder
        const nonce = 17;
        const amount = 1;
        const latestBlock = await ethers.provider.getBlock('latest');
        const expiry = latestBlock.timestamp + 3600;
        const signature = await getMintSignature(owner, littercoinAddress, user1.address, amount, nonce, expiry);
        await expect(littercoin.connect(user1).mint(amount, nonce, expiry, signature))
            .to.be.revertedWith("Merchants cannot mint Littercoin");
    });

    it("should prevent minting a Merchant Token to an address that already has one", async function () {
        // Mint a Merchant Token to user1
        await merchantToken.connect(owner).mint(user1.address, merchantTokenExpiry);

        // Attempt to mint another Merchant Token to the same address
        await expect(merchantToken.connect(owner).mint(user1.address, merchantTokenExpiry))
            .to.be.revertedWith("User already has a token");
    });

    it("should prevent merchants from transferring Littercoin tokens", async function () {
        // Mint 1 Littercoin token for user1
        await mintLittercoinForUser(user1, 1);

        // Mint Merchant Token to user2 (merchant)
        await merchantToken.connect(owner).mint(user2.address, merchantTokenExpiry);

        // Transfer Littercoin token from user1 to user2 (merchant)
        await littercoin.connect(user1).transferFrom(user1.address, user2.address, 1);

        // Attempt to transfer Littercoin token from merchant (user2) to user3
        await expect(littercoin.connect(user2).transferFrom(user2.address, user3.address, 1))
            .to.be.revertedWith("Token has already been transferred");
    });

    it("should not allow merchants to burn Littercoin tokens they do not own", async function () {
        // Mint Littercoin token to user1
        await mintLittercoinForUser(user1, 1);

        // Mint Merchant Token to user2 (merchant)
        await merchantToken.connect(owner).mint(user2.address, merchantTokenExpiry);

        // Send littercoin to the contract
        await user1.sendTransaction({ to: littercoin.getAddress(), value: ethers.parseEther("1") });

        // Attempt to burn the token by user2 (merchant), who does not own it
        await expect(littercoin.connect(user2).burnLittercoin([1]))
            .to.be.revertedWith("Caller must own all tokens being redeemed.");
    });

    it("should prevent minting a Merchant Token to the zero address", async function () {
        // Attempt to mint a Merchant Token to zero address
        await expect(merchantToken.connect(owner).mint(ethers.ZeroAddress, merchantTokenExpiry))
            .to.be.revertedWith("Cannot mint to zero address");
    });

    it("should allow users to burn their own Merchant Tokens", async function () {
        // Mint a Merchant Token to user1
        await merchantToken.connect(owner).mint(user1.address, merchantTokenExpiry);

        // Check balance before burning
        let balance = await merchantToken.balanceOf(user1.address);
        expect(balance).to.equal(1);

        // User1 burns their Merchant Token
        await merchantToken.connect(user1).burn();

        // Check balance after burning
        balance = await merchantToken.balanceOf(user1.address);
        expect(balance).to.equal(0);
    });

    it("should not allow users to burn Merchant Tokens when the contract is paused", async function () {
        // Mint a Merchant Token to user1
        await merchantToken.connect(owner).mint(user1.address, merchantTokenExpiry);

        // Pause the MerchantToken contract
        await merchantToken.connect(owner).pause();

        // Attempt to burn the Merchant Token
        await expect(merchantToken.connect(user1).burn())
            .to.be.revertedWith("Pausable: paused");

        // Unpause the MerchantToken contract
        await merchantToken.connect(owner).unpause();

        // Now burning should work
        await merchantToken.connect(user1).burn();

        // Check balance after burning
        const balance = await merchantToken.balanceOf(user1.address);
        expect(balance).to.equal(0);
    });

    // Helper function to mint Littercoin for a User
    async function mintLittercoinForUser (user, amount) {
        const nonce = 1;
        const block = await ethers.provider.getBlock('latest');
        const expiry = block.timestamp + 3600;
        const signature = await getMintSignature(owner, littercoinAddress, user.address, amount, nonce, expiry);

        return littercoin.connect(user).mint(amount, nonce, expiry, signature);
    }

    async function getMintSignature (signer, contractAddress, userAddress, amount, nonce, expiry) {
        const chainIt = BigInt((await signer.provider.getNetwork()).chainId);

        // Define the EIP-712 Domain
        const domain = {
            name: 'Littercoin',
            version: '1',
            chainId: chainIt,
            verifyingContract: contractAddress
        };

        // Define the types used in the signature
        const types = {
            Mint: [
                { name: 'user', type: 'address' },
                { name: 'amount', type: 'uint256' },
                { name: 'nonce', type: 'uint256' },
                { name: 'expiry', type: 'uint256' }
            ]
        };

        // The data to sign
        const value = {
            user: userAddress,
            amount: BigInt(amount),
            nonce: BigInt(nonce),
            expiry: BigInt(expiry)
        };

        // Generate the signature using EIP-712
        return await signer.signTypedData(domain, types, value);
    }
});
