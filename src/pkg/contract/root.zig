pub const Contract = @import("contract.zig").Contract;
pub const Error = @import("contract.zig").Error;
pub const parseOffset = @import("contract.zig").parseOffset;
pub const parseId = @import("contract.zig").parseId;

test {
    _ = @import("contract.zig");
}
