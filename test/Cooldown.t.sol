// SPDX-License-Identifier: CAL
pragma solidity =0.8.18;

import "forge-std/Test.sol";
import "../src/Cooldown.sol";

contract ReenterCooldown {
    function reenter() external {
        ExternalCooldown(msg.sender).withCooldown();
    }
}

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

    function withCooldown2() external onlyAfterCooldown {
        return;
    }

    function withCooldownReentrant(ReenterCooldown reenter_) external onlyAfterCooldown {
        reenter_.reenter();
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

    function testUninitialized(address alice_) public {
        vm.startPrank(alice_);
        ExternalCooldown cooldown_ = new ExternalCooldown();
        vm.expectRevert(Uninitialized.selector);
        cooldown_.withCooldown();
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

    function testCallerClear(uint32 cooldownDuration_, address alice_) public {
        vm.assume(cooldownDuration_ > 0);

        vm.startPrank(alice_);
        ExternalCooldown cooldown_ = new ExternalCooldown();
        cooldown_.initialize(cooldownDuration_);
        assertEq(address(0), cooldown_.caller());
        cooldown_.withCooldown();
        assertEq(address(0), cooldown_.caller());
    }

    function testOnlyAfterCooldownDuration(uint32 cooldownDuration_, uint32 intermediateDuration_, address alice_)
        public
    {
        vm.assume(cooldownDuration_ > 0);
        vm.assume(intermediateDuration_ < cooldownDuration_);
        ExternalCooldown cooldown_ = new ExternalCooldown();
        cooldown_.initialize(cooldownDuration_);

        vm.startPrank(alice_);
        uint256 expectedExpiry_ = block.timestamp + cooldownDuration_;
        uint256 intermediateTime_ = block.timestamp + intermediateDuration_;

        assertEq(0, cooldown_.expiry(alice_));
        cooldown_.withCooldown();
        assertEq(expectedExpiry_, cooldown_.expiry(alice_));

        // error immediately.
        vm.expectRevert(abi.encodeWithSelector(ActiveCooldown.selector, alice_, alice_, expectedExpiry_));
        cooldown_.withCooldown();

        vm.warp(intermediateTime_);
        vm.expectRevert(abi.encodeWithSelector(ActiveCooldown.selector, alice_, alice_, expectedExpiry_));
        cooldown_.withCooldown();

        // error 1 second before cooldown expiry.
        vm.warp(expectedExpiry_ - 1);
        vm.expectRevert(abi.encodeWithSelector(ActiveCooldown.selector, alice_, alice_, expectedExpiry_));
        cooldown_.withCooldown();

        vm.warp(expectedExpiry_);
        assertEq(expectedExpiry_, cooldown_.expiry(alice_));
        cooldown_.withCooldown();
        assertEq(expectedExpiry_ + cooldownDuration_, cooldown_.expiry(alice_));
    }

    function testOnlyAfterCooldownTwoCallers(uint32 cooldownDuration_, address alice_, address bob_) public {
        vm.assume(cooldownDuration_ > 0);
        vm.assume(alice_ != bob_);

        ExternalCooldown cooldown_ = new ExternalCooldown();
        cooldown_.initialize(cooldownDuration_);

        for (uint256 i_ = 0; i_ < 5; i_++) {
            uint256 expectedCooldownExpiry_ = block.timestamp + cooldownDuration_;

            // Alice triggers cooldown.
            vm.startPrank(alice_);
            vm.expectEmit(false, false, false, true);
            emit CooldownTriggered(alice_, expectedCooldownExpiry_);
            cooldown_.withCooldown();

            // She can't call again.
            vm.expectRevert(abi.encodeWithSelector(ActiveCooldown.selector, alice_, alice_, expectedCooldownExpiry_));
            cooldown_.withCooldown();
            vm.stopPrank();

            // Bob can still call.
            vm.startPrank(bob_);
            vm.expectEmit(false, false, false, true);
            emit CooldownTriggered(bob_, expectedCooldownExpiry_);
            cooldown_.withCooldown();

            // Bob can't call now
            vm.expectRevert(abi.encodeWithSelector(ActiveCooldown.selector, bob_, bob_, expectedCooldownExpiry_));
            cooldown_.withCooldown();
            vm.stopPrank();

            // Cooldowns expire.
            vm.warp(block.timestamp + cooldownDuration_);
        }
    }

    function testGlobalCooldown(uint32 cooldownDuration_, address alice_) public {
        vm.assume(cooldownDuration_ > 0);

        ExternalCooldown cooldown_ = new ExternalCooldown();
        cooldown_.initialize(cooldownDuration_);

        vm.startPrank(alice_);
        uint256 expectedExpiry_ = block.timestamp + cooldownDuration_;
        cooldown_.withCooldown();

        // The second cooldown function also errors.
        vm.expectRevert(abi.encodeWithSelector(ActiveCooldown.selector, alice_, alice_, expectedExpiry_));
        cooldown_.withCooldown2();
    }

    function testReentrantCooldown(uint32 cooldownDuration_, address alice_) public {
        vm.assume(cooldownDuration_ > 0);
        vm.assume(alice_ != address(0));

        ExternalCooldown cooldown_ = new ExternalCooldown();
        ReenterCooldown reenter_ = new ReenterCooldown();
        cooldown_.initialize(cooldownDuration_);

        vm.startPrank(alice_);
        uint256 expectedExpiry_ = block.timestamp + cooldownDuration_;

        vm.expectRevert(abi.encodeWithSelector(ActiveCooldown.selector, alice_, reenter_, expectedExpiry_));
        cooldown_.withCooldownReentrant(reenter_);
    }
}
