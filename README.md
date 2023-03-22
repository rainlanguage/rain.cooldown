# rain.cooldown

Docs at https://rainprotocol.github.io/rain.cooldown

`Cooldown` is a base contract that rate limits functions on the implementing
contract per `msg.sender`.

Each time a function with the `onlyAfterCooldown` modifier is called the
`msg.sender` must wait N seconds before calling any modified function.

This does nothing to prevent sybils who can generate an arbitrary number of
`msg.sender` values in parallel to spam a contract.

`Cooldown` is intended to prevent rapid state cycling to grief a contract, such
as rapidly locking and unlocking a large amount of capital in the `SeedERC20`
contract.

Requiring a lock/deposit of significant economic stake that sybils will not have
access to AND applying a cooldown IS a sybil mitigation. The economic stake alone
is NOT sufficient if gas is cheap as sybils can cycle the same stake between each
other. The cooldown alone is NOT sufficient as many sybils can be created, each
as a new `msg.sender`.