// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

abstract contract TestActors is Test {
    address constant alice = address(uint160(uint256(keccak256("alice"))));
    address constant bob = address(uint160(uint256(keccak256("bob"))));
    address constant charlie = address(uint160(uint256(keccak256("charlie"))));
    address constant david = address(uint160(uint256(keccak256("david"))));
    address constant ethan = address(uint160(uint256(keccak256("ethan"))));
    address constant fred = address(uint160(uint256(keccak256("fred"))));

    function setUp() public virtual {
        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
        vm.label(charlie, "Charlie");
        vm.label(david, "David");
        vm.label(ethan, "Ethan");
        vm.label(fred, "Fred");
    }
}
