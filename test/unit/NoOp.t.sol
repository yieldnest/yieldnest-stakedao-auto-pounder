// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

contract NoOpTest is Test {
    function test_noop() public pure {
        assert(true);
    }
}
