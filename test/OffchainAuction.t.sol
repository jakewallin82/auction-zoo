// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import "../src/sealed-bid/offchain-auction/OffchainAuction.sol";
import "../src/sealed-bid/offchain-auction/IOffchainAuctionErrors.sol";
import "./utils/TestActors.sol";
import "./utils/TestERC721.sol";

contract OffchainAuctionTest is IOffchainAuctionErrors, TestActors {
    OffchainAuction auction;
    TestERC721 erc721;

    uint96 constant ONE_ETH = 10**18;
    uint96 constant MIN_BID = 10**18;
    uint96 constant MAX_BID = 2 * (10**18);
    uint96 constant BID_UNIT = 10**16;
    uint256 constant TOKEN_ID = 1;
    uint16 constant LE = 0;
    uint16 constant EQ = 1;
    uint16 constant GE = 2;

    function setUp() public override {
        super.setUp();
        auction = new OffchainAuction();
        erc721 = new TestERC721();
        erc721.mint(alice, TOKEN_ID);
        hoax(alice);
        erc721.setApprovalForAll(address(auction), true);
    }

    function testCreateAuction() external {
        OffchainAuction.Auction memory expectedAuction = OffchainAuction
            .Auction({
                seller: alice,
                startTime: uint32(block.timestamp + 1 hours),
                endOfBiddingPeriod: uint32(block.timestamp + 2 hours),
                endOfRevealPeriod: uint32(block.timestamp + 3 hours),
                numUnrevealedBids: 0,
                highestBid: ONE_ETH,
                secondHighestBid: ONE_ETH,
                highestBidder: address(0),
                secondHighestBidder: address(0),
                index: 1
            });
        OffchainAuction.Auction memory actualAuction = createAuction(TOKEN_ID);
        assertAuctionsEqual(actualAuction, expectedAuction);
    }

    function testFivePersonAuction() external {
        uint96 salePrice = (ONE_ETH + (15 * BID_UNIT));
        OffchainAuction.Auction memory expectedState = createAuction(TOKEN_ID);
        //Commitment Stage
        skip(1 hours + 30 minutes);
        uint256 collateral = 2 * ONE_ETH;
        commitmentStage(collateral);
        skip(1 hours);
        auction.endAuction(address(erc721), 1);

        assertEq(erc721.ownerOf(1), david, "owner of tokenId 1");

        expectedState.numUnrevealedBids = 0;
        //expectedState.highestBid = ONE_ETH + (20 * BID_UNIT);
        expectedState.highestBidder = david;
        expectedState.secondHighestBid = ONE_ETH + (15 * BID_UNIT);
        expectedState.secondHighestBidder = fred;
        assertAuctionsEqual(
            auction.getAuction(address(erc721), 1),
            expectedState
        );
    }

    ///////////////// 5 Person Auction Stages ///////////////
    function commitmentStage(uint256 collateral) private {
        uint96 bobPrice = ONE_ETH + (1 * BID_UNIT);
        uint96 charliePrice = ONE_ETH + (10 * BID_UNIT);
        uint96 davidPrice = (20 * BID_UNIT);
        uint96 ethanPrice = (4 * BID_UNIT);
        uint96 fredPrice = (15 * BID_UNIT);
        bytes32 bobComm = commitBid(
            TOKEN_ID,
            bob,
            bobPrice,
            collateral,
            bytes32(uint256(123))
        );
        bytes32 charComm = commitBid(
            TOKEN_ID,
            charlie,
            charliePrice,
            collateral,
            bytes32(uint256(234))
        );
        bytes32 davComm = commitBid(
            TOKEN_ID,
            david,
            davidPrice,
            collateral,
            bytes32(uint256(234))
        );
        bytes32 ethComm = commitBid(
            TOKEN_ID,
            ethan,
            ethanPrice,
            collateral,
            bytes32(uint256(234))
        );
        bytes32 fredComm = commitBid(
            TOKEN_ID,
            fred,
            fredPrice,
            collateral,
            bytes32(uint256(234))
        );
        //Reveal Stage
        skip(1 hours);

        uint96 salePrice = (ONE_ETH + (15 * BID_UNIT));
        hoax(bob);
        auction.submitProof(
            address(erc721),
            TOKEN_ID,
            traverseHashChain(bobComm, salePrice - bobPrice),
            0,
            salePrice
        );
        hoax(charlie);
        auction.submitProof(
            address(erc721),
            TOKEN_ID,
            traverseHashChain(charComm, salePrice - charliePrice),
            0,
            salePrice
        );
        hoax(david);
        auction.submitProof(address(erc721), TOKEN_ID, davComm, 2, salePrice);
        hoax(ethan);
        auction.submitProof(
            address(erc721),
            TOKEN_ID,
            traverseHashChain(ethComm, salePrice - ethanPrice),
            0,
            salePrice
        );
        hoax(fred);
        auction.submitProof(address(erc721), TOKEN_ID, fredComm, 1, salePrice);
    }

    function traverseHashChain(bytes32 salt, uint256 bidValue)
        internal
        pure
        returns (bytes32)
    {
        uint256 i;
        for (i = MAX_BID; i > bidValue; i -= BID_UNIT) {
            salt = keccak256(abi.encode(salt));
        }
        return salt;
    }

    function assertProofStage() private {
        uint64 auctionIndex = 1;
        assertBidProof(auctionIndex, bob, LE, "bob");
        assertBidProof(auctionIndex, charlie, LE, "charlie");
        assertBidProof(auctionIndex, david, GE, "david");
        assertBidProof(auctionIndex, ethan, LE, "ethan");
        assertBidProof(auctionIndex, fred, EQ, "fred");
    }

    ////////////////////////////////////////////////////////

    function createAuction(uint256 tokenId)
        private
        returns (OffchainAuction.Auction memory a)
    {
        hoax(alice);
        auction.createAuction(
            address(erc721),
            tokenId,
            uint32(block.timestamp + 1 hours),
            1 hours,
            1 hours,
            ONE_ETH
        );
        return auction.getAuction(address(erc721), tokenId);
    }

    function commitBid(
        uint256 tokenId,
        address from,
        uint96 bidValue,
        uint256 collateral,
        bytes32 nonce
    ) private returns (bytes32 salt) {
        salt = keccak256(
            abi.encode(
                nonce,
                bidValue,
                address(erc721),
                tokenId,
                1 // auction index
            )
        );
        //create hash-chain of length x
        uint256 i;
        for (i = MAX_BID; i > bidValue; i -= BID_UNIT) {
            salt = keccak256(abi.encode(salt));
        }
        bytes20 commitment = bytes20(salt);

        hoax(from);
        auction.commitBid{value: collateral}(
            address(erc721),
            tokenId,
            commitment
        );
    }

    function assertBid(
        uint64 auctionIndex,
        address bidder,
        bytes20 commitment,
        uint256 collateral,
        uint64 numUnrevealedBids
    ) private {
        (
            bytes20 storedCommitment,
            uint96 storedCollateral,
            uint96 storedRevealed
        ) = auction.bids(address(erc721), TOKEN_ID, auctionIndex, bidder);
        //assertEq(storedCommitment, commitment, "commitment");
        assertEq(storedCollateral, collateral, "collateral");
        assertEq(
            auction.getAuction(address(erc721), 1).numUnrevealedBids,
            numUnrevealedBids,
            "numUnrevealedBids"
        );
    }

    function assertBidProof(
        uint64 auctionIndex,
        address bidder,
        uint16 label,
        string memory name
    ) private {
        (
            bytes20 storedCommitment,
            uint96 storedCollateral,
            uint16 storedRevealed
        ) = auction.bids(address(erc721), TOKEN_ID, auctionIndex, bidder);
        (bytes32 storedHashNode, uint16 storedLabel) = auction.bidProofs(
            address(erc721),
            TOKEN_ID,
            auctionIndex,
            bidder
        );
        assertEq(storedLabel, label, "AuctionLabel");
        assertEq(storedCollateral, 0, "Collateral");
        assertEq(
            auction.getAuction(address(erc721), 1).numUnrevealedBids,
            0,
            "numUnrevealedBids"
        );
        if (storedLabel != 2) {
            uint256 i;
            uint96 limit = MAX_BID -
                auction.getAuction(address(erc721), 1).secondHighestBid;
            for (i = 0; i < limit; i += BID_UNIT) {
                storedHashNode = keccak256(abi.encode(storedHashNode));
            }
            assertEq(
                bytes20(storedHashNode),
                storedCommitment,
                string.concat("Proof vs Commitment: ", name)
            );
        }
    }

    function assertAuctionsEqual(
        OffchainAuction.Auction memory actualAuction,
        OffchainAuction.Auction memory expectedAuction
    ) private {
        assertEq(actualAuction.seller, expectedAuction.seller, "seller");
        assertEq(
            actualAuction.startTime,
            expectedAuction.startTime,
            "startTime"
        );
        assertEq(
            actualAuction.endOfBiddingPeriod,
            expectedAuction.endOfBiddingPeriod,
            "endOfBiddingPeriod"
        );
        assertEq(
            actualAuction.endOfRevealPeriod,
            expectedAuction.endOfRevealPeriod,
            "endOfRevealPeriod"
        );
        assertEq(
            actualAuction.numUnrevealedBids,
            expectedAuction.numUnrevealedBids,
            "numUnrevealedBids"
        );
        assertEq(
            actualAuction.highestBid,
            expectedAuction.highestBid,
            "highestBid"
        );
        assertEq(
            actualAuction.secondHighestBid,
            expectedAuction.secondHighestBid,
            "secondHighestBid"
        );
        assertEq(
            actualAuction.highestBidder,
            expectedAuction.highestBidder,
            "highestBidder"
        );
        assertEq(actualAuction.index, expectedAuction.index, "index");
    }
}
