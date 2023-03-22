// SPDX-License-Identifier: CAL
pragma solidity =0.8.18;

import "forge-std/Test.sol";
import "../src/Cooldown.sol";

contract ExternalCooldown is Cooldown {
}

contract CooldownTest is Test, Cooldown {

    function testZeroCooldown() public {
        vm.expectRevert(ZeroInitCooldown.selector);
        initializeCooldown(0);
    }

}