pub const Error = error{ ContractKeyNotFound, ContractInvalidValue };

pub const Location = enum {
    Header,
    Query,
    Path,
    Body,
};

/// Declares one request input: where it lives and an optional default.
pub const Contract = struct {
    key: []const u8,
    location: Location,
    default_value: ?[]const u8 = null,

    /// The raw value, or null when absent (the default is not applied).
    pub fn opt(self: @This(), req: *httpz.Request) ?[]const u8 {
        return switch (self.location) {
            .Header => req.header(self.key),
            .Path => req.param(self.key),
            .Query => if (req.query()) |kv| kv.get(self.key) else |_| null,
            .Body => if (req.formData()) |kv| kv.get(self.key) else |_| null,
        };
    }

    /// The value, else the default, else `ContractKeyNotFound`.
    pub fn get(self: @This(), req: *httpz.Request) Error![]const u8 {
        return self.opt(req) orelse self.default_value orelse {
            std.log.debug("contract key not found: {s}", .{self.key});
            return error.ContractKeyNotFound;
        };
    }

    /// A positive 32-bit id (digits only).
    pub fn getId(self: @This(), req: *httpz.Request) Error!i32 {
        return parseId(try self.get(req)) orelse error.ContractInvalidValue;
    }
};

/// Strict "[0-9]+" id parse: positive, fits in i32 (std's parseInt also takes '+' and '_').
pub fn parseId(s: []const u8) ?i32 {
    if (s.len == 0 or s.len > 10) return null;
    for (s) |c| if (!std.ascii.isDigit(c)) return null;
    const v = std.fmt.parseInt(i32, s, 10) catch return null;
    return if (v > 0) v else null;
}

/// A non-negative offset that fits Postgres `int` (digits only).
pub fn parseOffset(s: []const u8) ?u32 {
    if (s.len == 0 or s.len > 10) return null;
    for (s) |c| if (!std.ascii.isDigit(c)) return null;
    const v = std.fmt.parseInt(u32, s, 10) catch return null;
    return if (v <= std.math.maxInt(i32)) v else null;
}

test "parseOffset bounds" {
    try std.testing.expectEqual(@as(?u32, 0), parseOffset("0"));
    try std.testing.expectEqual(@as(?u32, 2147483647), parseOffset("2147483647"));
    for ([_][]const u8{ "", "-1", "2147483648", "4294967295", "99999999999" }) |bad| {
        try std.testing.expectEqual(@as(?u32, null), parseOffset(bad));
    }
}

test "parseId" {
    try std.testing.expectEqual(@as(?i32, 12), parseId("12"));
    for ([_][]const u8{ "", "0", "-1", "+1", "1_0", "x", "2147483648" }) |bad| {
        try std.testing.expectEqual(@as(?i32, null), parseId(bad));
    }
}

const std = @import("std");
const httpz = @import("httpz");
