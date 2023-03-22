// SPDX-License-Identifier: CAL
pragma solidity =0.8.18;

import "forge-std/Test.sol";
import "../src/Cooldown.sol";

contract ExternalCooldown is Cooldown {
    function duration() external view returns (uint256) {
        return cooldownDuration;
    }

    function expiry(address account_) external view returns (uint256) {
        return cooldownExpiries[account_];
    }

    function caller() external view returns (address) {
        return cooldownCaller;
    }

    function initialize(uint32 cooldownDuration_) external {
        initializeCooldown(cooldownDuration_);
    }

    function withCooldown() external onlyAfterCooldown {
        return;
    }
}

contract CooldownTest is Test, Cooldown {
    function testZeroCooldown() public {
        ExternalCooldown cooldown_ = new ExternalCooldown();
        vm.expectRevert(ZeroInitCooldown.selector);
        cooldown_.initialize(0);
    }

    function testZeroCooldown(uint32 a_, uint32 b_) public {
        vm.assume(a_ > 0);
        vm.assume(b_ > 0);

        ExternalCooldown cooldown_ = new ExternalCooldown();
        cooldown_.initialize(a_);
        vm.expectRevert(Reinitialize.selector);
        cooldown_.initialize(b_);
    }

    function testInitializeCooldown(uint32 cooldownDuration_, address alice_) public {
        vm.assume(cooldownDuration_ > 0);

        vm.startPrank(alice_);
        ExternalCooldown cooldown_ = new ExternalCooldown();
        vm.expectEmit(false, false, false, true);
        emit CooldownInitialize(alice_, uint256(cooldownDuration_));
        cooldown_.initialize(cooldownDuration_);
        assertEq(cooldownDuration_, cooldown_.duration());
    }

    function testOnlyAfterCooldown(uint32 cooldownDuration_, address alice_, address bob_) public {
        vm.assume(cooldownDuration_ > 0);
        vm.assume(alice_ != bob_);

        ExternalCooldown cooldown_ = new ExternalCooldown();
        cooldown_.initialize(cooldownDuration_);

        for (uint256 i_ = 0; i_ < 5; i_++) {
            // Alice triggers cooldown.
            vm.startPrank(alice_);
            cooldown_.withCooldown();

            // She can't call again.
            vm.expectRevert(
                abi.encodeWithSelector(
                    ActiveCooldown.selector, alice_, block.timestamp + cooldownDuration_, block.timestamp
                )
            );
            cooldown_.withCooldown();
            vm.stopPrank();

            // Bob can still call.
            vm.startPrank(bob_);
            cooldown_.withCooldown();

            // Bob can't call now
            vm.expectRevert(
                abi.encodeWithSelector(
                    ActiveCooldown.selector, bob_, block.timestamp + cooldownDuration_, block.timestamp
                )
            );
            cooldown_.withCooldown();
            vm.stopPrank();

            // Cooldowns expire.
            vm.warp(block.timestamp + cooldownDuration_);
        }
    }
}
