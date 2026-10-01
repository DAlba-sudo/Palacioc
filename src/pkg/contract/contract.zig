// pub const Contract = struct {
//     key: []const u8,
// };

pub const Location = enum {
    Header,
    Query,
    Path,
    Body,
};

pub const Contract = struct {
    key: []const u8,
    location: Location,
    default_value: ?[]const u8 = null,

    pub fn get(self: @This(), req: *httpz.Request) ![]const u8 {
        switch (self.location) {
            .Header => {
                const value = req.header(self.key);
                if (value) |v| {
                    return v;
                }
            },
            .Query => {
                const kv = req.query() catch {
                    std.log.err("failed to get query parameters for contract request", .{});
                    return error.ContractKeyNotFound;
                };

                if (kv.get(self.key)) |v| {
                    return v;
                }
            },
            .Path => {
                const value = req.param(self.key);
                if (value) |v| {
                    return v;
                }
            },
            .Body => {
                const kv = req.formData() catch {
                    std.log.err("failed to get form data for contract request", .{});
                    return error.ContractKeyNotFound;
                };

                if (kv.get(self.key)) |v| {
                    return v;
                }
            },
        }

        std.log.debug("contract key not found: {s}", .{self.key});
        if (self.default_value) |v| {
            std.log.debug("returning default value for contract key: {s}", .{v});
            return v;
        } else {
            std.log.debug("no default value provided for contract key: {s}", .{self.key});
            return error.ContractKeyNotFound;
        }
    }
};

const std = @import("std");
const httpz = @import("httpz");
