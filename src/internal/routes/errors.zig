//! One place that turns handler errors into responses: `{"err": msg}` for
//! /api paths, an HTMX flash fragment for everything else.
pub const Mapped = struct { status: std.http.Status, msg: []const u8 };

pub fn map(err: anyerror) Mapped {
    inline for (@typeInfo(validate.Error).error_set.?) |e| {
        if (err == @field(validate.Error, e.name)) return .{ .status = .bad_request, .msg = validate.message(@field(validate.Error, e.name)) };
    }
    return switch (err) {
        error.ContractKeyNotFound => .{ .status = .bad_request, .msg = "Missing required parameter." },
        error.ContractInvalidValue => .{ .status = .bad_request, .msg = "Invalid parameter." },
        error.NotFound => .{ .status = .not_found, .msg = "Not found." },
        error.NoDatabase => .{ .status = .service_unavailable, .msg = "Database not connected." },
        else => blk: {
            std.log.err("unhandled error: {s}", .{@errorName(err)});
            break :blk .{ .status = .internal_server_error, .msg = "Internal server error." };
        },
    };
}

pub fn respond(req: *httpz.Request, res: *httpz.Response, err: anyerror) void {
    const m = map(err);
    if (std.mem.startsWith(u8, req.url.path, "/api/")) {
        res.setStatus(m.status);
        res.json(.{ .err = m.msg }, .{}) catch {
            res.body = "{\"err\":\"Internal server error.\"}";
        };
    } else if (render.isFragment(req)) {
        render.flash(res, m.status, m.msg);
    } else {
        res.setStatus(m.status); // a plain navigation: no #flash to retarget
        res.content_type = .TEXT;
        res.body = m.msg;
    }
}

const std = @import("std");
const httpz = @import("httpz");
const validate = @import("../types/root.zig").validate;
const render = @import("../web/render.zig");

test "map" {
    try std.testing.expectEqual(std.http.Status.bad_request, map(error.TitleRequired).status);
    try std.testing.expectEqual(std.http.Status.bad_request, map(error.ContractInvalidValue).status);
    try std.testing.expectEqual(std.http.Status.not_found, map(error.NotFound).status);
    try std.testing.expectEqual(std.http.Status.service_unavailable, map(error.NoDatabase).status);
}
