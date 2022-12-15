// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import "../src/sealed-bid/vex-auction/VexAuction.sol";
import "../src/sealed-bid/vex-auction/IVexAuctionErrors.sol";
import "./utils/TestActors.sol";
import "./utils/TestERC721.sol";

contract VexAuctionTest is IVexAuctionErrors, TestActors {
    VexAuction auction;
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
        auction = new VexAuction();
        erc721 = new TestERC721();
        erc721.mint(alice, TOKEN_ID);
        hoax(alice);
        erc721.setApprovalForAll(address(auction), true);
    }

    function testCreateAuction() external {
        VexAuction.Auction memory expectedAuction = VexAuction.Auction({
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
        VexAuction.Auction memory actualAuction = createAuction(TOKEN_ID);
        assertAuctionsEqual(actualAuction, expectedAuction);
    }

    function testCannotCreateAuctionForItemThatYouDoNotOwn() external {
        vm.expectRevert("WRONG_FROM");
        createAuction(4);
    }

    function testCommitBid() external {
        createAuction(TOKEN_ID);
        skip(1 hours + 30 minutes);
        uint256 collateral = 2 * ONE_ETH;
        bytes20 commitment = commitBid(
            TOKEN_ID,
            bob,
            ONE_ETH + 1,
            collateral,
            bytes32(uint256(123))
        );
        assertBid(1, bob, commitment, collateral, 1);
    }

    function testCannotCommitBidIfAuctionIsNotActive() external {
        vm.expectRevert(NotInBidPeriodError.selector);
        commitBid(
            TOKEN_ID,
            bob,
            ONE_ETH + 1,
            2 * ONE_ETH,
            bytes32(uint256(123))
        );
    }

    function testCannotCommitBidBeforeBiddingPeriod() external {
        createAuction(TOKEN_ID);
        skip(59 minutes);
        vm.expectRevert(NotInBidPeriodError.selector);
        commitBid(
            TOKEN_ID,
            bob,
            ONE_ETH + 1,
            2 * ONE_ETH,
            bytes32(uint256(123))
        );
    }

    function testCannotCommitBidAfterBiddingPeriod() external {
        createAuction(TOKEN_ID);
        skip(2 hours + 1);
        vm.expectRevert(NotInBidPeriodError.selector);
        commitBid(
            TOKEN_ID,
            bob,
            ONE_ETH + 1,
            2 * ONE_ETH,
            bytes32(uint256(123))
        );
    }

    function testCanUpdateCommitment() external {
        createAuction(TOKEN_ID);
        skip(1 hours + 30 minutes);
        uint256 collateral = 2 * ONE_ETH;
        commitBid(
            TOKEN_ID,
            bob,
            ONE_ETH + 1,
            collateral,
            bytes32(uint256(123))
        );
        bytes20 commitment = commitBid(
            TOKEN_ID,
            bob,
            ONE_ETH + 2,
            0, // Do not add additional collateral
            bytes32(uint256(123))
        );
        assertBid(1, bob, commitment, collateral, 1);
    }

    function testCanAddCollateral() external {
        createAuction(TOKEN_ID);
        skip(1 hours + 30 minutes);
        uint256 collateral = 2 * ONE_ETH;
        commitBid(
            TOKEN_ID,
            bob,
            ONE_ETH + 1,
            collateral / 2,
            bytes32(uint256(123))
        );
        bytes20 commitment = commitBid(
            TOKEN_ID,
            bob,
            ONE_ETH + 1, // same bid
            collateral / 2, // add collateral
            bytes32(uint256(123))
        );
        assertBid(1, bob, commitment, collateral, 1);
    }

    function testRevealBid() external {
        VexAuction.Auction memory expectedState = createAuction(TOKEN_ID);
        skip(1 hours + 30 minutes);
        uint256 collateral = 2 * ONE_ETH;
        uint96 bidValue = ONE_ETH + BID_UNIT;
        bytes32 nonce = bytes32(uint256(123));
        commitBid(TOKEN_ID, bob, bidValue, collateral, nonce);
        skip(1 hours);
        hoax(bob);
        auction.revealBid(address(erc721), TOKEN_ID, bidValue, nonce);

        expectedState.numUnrevealedBids = 0; // the only bid was revealed
        expectedState.highestBid = bidValue;
        expectedState.highestBidder = bob;
        assertAuctionsEqual(
            auction.getAuction(address(erc721), 1),
            expectedState
        );
    }

    function testCannotRevealBidAfterRevealPeriod() external {
        createAuction(TOKEN_ID);
        skip(1 hours + 30 minutes);
        uint256 collateral = 2 * ONE_ETH;
        uint96 bidValue = ONE_ETH + BID_UNIT;
        bytes32 nonce = bytes32(uint256(123));
        commitBid(TOKEN_ID, bob, bidValue, collateral, nonce);
        skip(2 hours);
        vm.expectRevert(NotInRevealPeriodError.selector);
        hoax(bob);
        auction.revealBid(address(erc721), TOKEN_ID, bidValue, nonce);
    }

    function testCannotRevealUsingDifferentNonce() external {
        createAuction(TOKEN_ID);
        skip(1 hours + 30 minutes);
        uint256 collateral = 2 * ONE_ETH;
        uint96 bidValue = ONE_ETH + BID_UNIT;
        bytes32 nonce = bytes32(uint256(123));
        bytes20 commitment = commitBid(
            TOKEN_ID,
            bob,
            bidValue,
            collateral,
            nonce
        );
        skip(1 hours);
        bytes32 wrongNonce = bytes32(uint256(nonce) + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                InvalidOpeningError.selector,
                bytes20(
                    keccak256(
                        abi.encode(
                            wrongNonce,
                            bidValue,
                            address(erc721),
                            TOKEN_ID,
                            1
                        )
                    )
                ),
                commitment
            )
        );
        hoax(bob);
        auction.revealBid(address(erc721), TOKEN_ID, bidValue, wrongNonce);
    }

    function testCannotRevealUsingDifferentBidValue() external {
        createAuction(TOKEN_ID);
        skip(1 hours + 30 minutes);
        uint256 collateral = 2 * ONE_ETH;
        uint96 bidValue = ONE_ETH + (3 * BID_UNIT);
        bytes32 nonce = bytes32(uint256(123));
        bytes20 commitment = commitBid(
            TOKEN_ID,
            bob,
            bidValue,
            collateral,
            nonce
        );
        skip(1 hours);
        uint96 wrongValue = bidValue + BID_UNIT;
        vm.expectRevert(
            abi.encodeWithSelector(
                InvalidOpeningError.selector,
                bytes20(
                    keccak256(
                        abi.encode(
                            nonce,
                            wrongValue,
                            address(erc721),
                            TOKEN_ID,
                            1
                        )
                    )
                ),
                commitment
            )
        );
        hoax(bob);
        auction.revealBid(address(erc721), TOKEN_ID, wrongValue, nonce);
    }

    function testRevealWithInsufficientCollateral() external {
        VexAuction.Auction memory expectedState = createAuction(TOKEN_ID);
        skip(1 hours + 30 minutes);
        uint256 collateral = ONE_ETH;
        uint96 bidValue = ONE_ETH + 1;
        bytes32 nonce = bytes32(uint256(123));
        commitBid(TOKEN_ID, bob, bidValue, collateral, nonce);
        skip(1 hours);
        hoax(bob);
        auction.revealBid(address(erc721), TOKEN_ID, bidValue, nonce);
        assertAuctionsEqual(
            auction.getAuction(address(erc721), TOKEN_ID),
            expectedState
        );
        assertBid(
            1,
            bob,
            bytes20(0), // commitment was cleared
            0, // collateral was zeroed
            0
        );
    }

    function testUpdateHighestBidder() external {
        VexAuction.Auction memory expectedState = createAuction(TOKEN_ID);
        skip(1 hours + 30 minutes);
        uint256 collateral = 2 * ONE_ETH;
        commitBid(
            TOKEN_ID,
            bob,
            ONE_ETH + 1,
            collateral,
            bytes32(uint256(123))
        );
        commitBid(
            TOKEN_ID,
            charlie,
            ONE_ETH + 2,
            collateral,
            bytes32(uint256(234))
        );
        skip(1 hours);
        hoax(bob);
        auction.revealBid(
            address(erc721),
            TOKEN_ID,
            ONE_ETH + 1,
            bytes32(uint256(123))
        );
        expectedState.numUnrevealedBids = 1;
        expectedState.highestBid = ONE_ETH + 1;
        expectedState.highestBidder = bob;
        assertAuctionsEqual(
            auction.getAuction(address(erc721), 1),
            expectedState
        );
        hoax(charlie);
        auction.revealBid(
            address(erc721),
            TOKEN_ID,
            ONE_ETH + 2,
            bytes32(uint256(234))
        );
        expectedState.numUnrevealedBids = 0;
        expectedState.highestBid = ONE_ETH + 2;
        expectedState.highestBidder = charlie;
        expectedState.secondHighestBid = ONE_ETH + 1;
        assertAuctionsEqual(
            auction.getAuction(address(erc721), 1),
            expectedState
        );
    }

    function testWithdrawsCollateralIfNotHighestBid() external {
        createAuction(TOKEN_ID);
        skip(1 hours + 30 minutes);
        uint256 collateral = 2 * ONE_ETH;
        uint96 bidValue = ONE_ETH;
        bytes32 nonce = bytes32(uint256(123));
        commitBid(TOKEN_ID, bob, bidValue, collateral, nonce);
        skip(1 hours);
        hoax(bob);
        uint256 bobBalanceBefore = bob.balance;
        auction.revealBid(address(erc721), TOKEN_ID, bidValue, nonce);
        assertEq(bob.balance, bobBalanceBefore + collateral, "bob's balance");
        assertBid(
            1,
            bob,
            bytes20(0), // commitment was cleared
            0, // collateral was zeroed
            0
        );
    }

    function testEndAuctionEarly() external {
        createAuction(TOKEN_ID);
        skip(1 hours + 30 minutes);
        uint256 collateral = 2 * ONE_ETH;
        commitBid(
            TOKEN_ID,
            bob,
            ONE_ETH + 1,
            collateral,
            bytes32(uint256(123))
        );
        commitBid(
            TOKEN_ID,
            charlie,
            ONE_ETH + 2,
            collateral,
            bytes32(uint256(234))
        );
        skip(1 hours);
        hoax(bob);
        auction.revealBid(
            address(erc721),
            TOKEN_ID,
            ONE_ETH + 1,
            bytes32(uint256(123))
        );
        hoax(charlie);
        auction.revealBid(
            address(erc721),
            TOKEN_ID,
            ONE_ETH + 2,
            bytes32(uint256(234))
        );
        uint256 aliceBalanceBefore = alice.balance;
        auction.endAuction(address(erc721), 1);
        assertEq(
            alice.balance,
            aliceBalanceBefore + (ONE_ETH + 1),
            "alice's balance"
        );
        assertEq(erc721.ownerOf(1), charlie, "owner of tokenId 1");
        assertBid(
            1,
            charlie,
            bytes20(0), // commitment was cleared
            0, // collateral was zeroed
            0
        );
    }

    function testCannotEndAuctionEarlyIfNotAllBidsRevealed() external {
        createAuction(TOKEN_ID);
        skip(1 hours + 30 minutes);
        uint256 collateral = 2 * ONE_ETH;
        commitBid(
            TOKEN_ID,
            bob,
            ONE_ETH + 1,
            collateral,
            bytes32(uint256(123))
        );
        commitBid(
            TOKEN_ID,
            charlie,
            ONE_ETH + 2,
            collateral,
            bytes32(uint256(234))
        );
        skip(1 hours);
        hoax(charlie);
        auction.revealBid(
            address(erc721),
            TOKEN_ID,
            ONE_ETH + 2,
            bytes32(uint256(234))
        );
        vm.expectRevert(RevealPeriodOngoingError.selector);
        auction.endAuction(address(erc721), 1);
    }

    function testCannotEndAuctionBeforeEndOfBidding() external {
        createAuction(TOKEN_ID);
        skip(1 hours + 30 minutes);
        uint256 collateral = 2 * ONE_ETH;
        commitBid(
            TOKEN_ID,
            bob,
            ONE_ETH + 1,
            collateral,
            bytes32(uint256(123))
        );
        commitBid(
            TOKEN_ID,
            charlie,
            ONE_ETH + 2,
            collateral,
            bytes32(uint256(234))
        );
        vm.expectRevert(BidPeriodOngoingError.selector);
        auction.endAuction(address(erc721), 1);
    }

    function testEndAuctionWithNoWinner() external {
        createAuction(TOKEN_ID);
        skip(1 hours + 30 minutes);
        skip(2 hours);
        auction.endAuction(address(erc721), 1);
        assertEq(erc721.ownerOf(1), alice, "owner of tokenId 1");
    }

    function testEndAuctionAfterRevealPeriod() external {
        createAuction(TOKEN_ID);
        skip(1 hours + 30 minutes);
        uint256 collateral = 2 * ONE_ETH;
        commitBid(
            TOKEN_ID,
            bob,
            ONE_ETH + 1,
            collateral,
            bytes32(uint256(123))
        );
        bytes20 charlieCommitment = commitBid(
            TOKEN_ID,
            charlie,
            ONE_ETH + 2,
            collateral,
            bytes32(uint256(234))
        );
        skip(1 hours);
        hoax(bob);
        auction.revealBid(
            address(erc721),
            TOKEN_ID,
            ONE_ETH + 1,
            bytes32(uint256(123))
        );
        skip(1 hours);
        uint256 aliceBalanceBefore = alice.balance;
        auction.endAuction(address(erc721), 1);
        assertEq(
            alice.balance,
            aliceBalanceBefore + ONE_ETH,
            "alice's balance"
        );
        assertEq(erc721.ownerOf(1), bob, "owner of tokenId 1");
        assertBid(
            1,
            bob,
            bytes20(0), // commitment was cleared
            0, // collateral was zeroed
            1 // charlie's bid was not revealed
        );
        assertBid(
            1,
            charlie,
            charlieCommitment, // commitment was not cleared
            collateral, // collateral was not zeroed
            1 // charlie's bid was not revealed
        );
    }

    function testCanWithdrawCollateralIfNotWinner() external {
        createAuction(TOKEN_ID);
        skip(1 hours + 30 minutes);
        uint256 collateral = 2 * ONE_ETH;
        commitBid(
            TOKEN_ID,
            bob,
            ONE_ETH + 1,
            collateral,
            bytes32(uint256(123))
        );
        commitBid(
            TOKEN_ID,
            charlie,
            ONE_ETH + 2,
            collateral,
            bytes32(uint256(234))
        );
        skip(1 hours);
        hoax(bob);
        auction.revealBid(
            address(erc721),
            TOKEN_ID,
            ONE_ETH + 1,
            bytes32(uint256(123))
        );
        hoax(charlie);
        auction.revealBid(
            address(erc721),
            TOKEN_ID,
            ONE_ETH + 2,
            bytes32(uint256(234))
        );
        hoax(bob);
        uint256 bobBalanceBefore = bob.balance;
        auction.withdrawCollateral(address(erc721), TOKEN_ID, 1);
        assertEq(bob.balance, bobBalanceBefore + collateral, "bob's balance");
        assertBid(
            1,
            bob,
            bytes20(0), // commitment was cleared
            0, // collateral was zeroed
            0
        );
    }

    function testCannotWithdrawCollateralWithoutRevealingBid() external {
        createAuction(TOKEN_ID);
        skip(1 hours + 30 minutes);
        uint256 collateral = 2 * ONE_ETH;
        commitBid(
            TOKEN_ID,
            bob,
            ONE_ETH + 1,
            collateral,
            bytes32(uint256(123))
        );
        commitBid(
            TOKEN_ID,
            charlie,
            ONE_ETH + 2,
            collateral,
            bytes32(uint256(234))
        );
        skip(1 hours);
        hoax(bob);
        vm.expectRevert(UnrevealedBidError.selector);
        auction.withdrawCollateral(address(erc721), TOKEN_ID, 1);
    }

    function testFivePersonAuction() external {
        VexAuction.Auction memory expectedState = createAuction(TOKEN_ID);
        //Commitment Stage
        skip(1 hours + 30 minutes);
        uint256 collateral = 2 * ONE_ETH;
        commitmentStage(collateral);

        //Reveal Stage
        skip(1 hours);
        revealStage(collateral);

        auction.endAuction(address(erc721), 1);
        uint96 bidPrice = (ONE_ETH + (15 * BID_UNIT));
        assertEq(erc721.ownerOf(1), david, "owner of tokenId 1");

        assertProofStage();

        expectedState.numUnrevealedBids = 0;
        expectedState.highestBid = ONE_ETH + (20 * BID_UNIT);
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
        commitBid(
            TOKEN_ID,
            bob,
            ONE_ETH + (1 * BID_UNIT),
            collateral,
            bytes32(uint256(123))
        );
        commitBid(
            TOKEN_ID,
            charlie,
            ONE_ETH + (10 * BID_UNIT),
            collateral,
            bytes32(uint256(234))
        );
        commitBid(
            TOKEN_ID,
            david,
            ONE_ETH + (20 * BID_UNIT),
            collateral,
            bytes32(uint256(234))
        );
        commitBid(
            TOKEN_ID,
            ethan,
            ONE_ETH + (4 * BID_UNIT),
            collateral,
            bytes32(uint256(234))
        );
        commitBid(
            TOKEN_ID,
            fred,
            ONE_ETH + (15 * BID_UNIT),
            collateral,
            bytes32(uint256(234))
        );
    }

    function revealStage(uint256 collateral) private {
        hoax(david);
        auction.revealBid(
            address(erc721),
            TOKEN_ID,
            ONE_ETH + (20 * BID_UNIT),
            bytes32(uint256(234))
        );
        hoax(fred);
        auction.revealBid(
            address(erc721),
            TOKEN_ID,
            ONE_ETH + (15 * BID_UNIT),
            bytes32(uint256(234))
        );
        hoax(ethan);
        auction.revealBid(
            address(erc721),
            TOKEN_ID,
            ONE_ETH + (4 * BID_UNIT),
            bytes32(uint256(234))
        );
        hoax(bob);
        uint256 bobBalanceBefore = bob.balance;
        auction.revealBid(
            address(erc721),
            TOKEN_ID,
            ONE_ETH + (1 * BID_UNIT),
            bytes32(uint256(123))
        );
        assertEq(bob.balance, bobBalanceBefore + collateral, "bob's balance");

        hoax(charlie);
        uint256 charlieBalanceBefore = charlie.balance;
        auction.revealBid(
            address(erc721),
            TOKEN_ID,
            ONE_ETH + (10 * BID_UNIT),
            bytes32(uint256(234))
        );
        assertEq(
            charlie.balance,
            charlieBalanceBefore + collateral,
            "charlie's balance"
        );
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
        returns (VexAuction.Auction memory a)
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
    ) private returns (bytes20 commitment) {
        bytes32 salt = keccak256(
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
        commitment = bytes20(salt);

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
        VexAuction.Auction memory actualAuction,
        VexAuction.Auction memory expectedAuction
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
