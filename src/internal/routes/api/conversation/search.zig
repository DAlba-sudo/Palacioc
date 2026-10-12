const c_text = contract.Contract{ .key = "s", .location = .Query, .default_value = "" };
const c_offset = contract.Contract{ .key = "p", .location = .Query, .default_value = "0" };
const c_limit = contract.Contract{ .key = "l", .location = .Query, .default_value = "10" };

pub const max_limit = 100;

/// GET /api/conversation/search?s=<title text>&p=<offset>&l=<limit, max 100>
pub fn search(app: App, req: *httpz.Request, res: *httpz.Response) !void {
    const p = try app.pool();
    const offset = std.fmt.parseInt(u32, try c_offset.get(req), 10) catch return error.ContractInvalidValue;
    const limit = std.fmt.parseInt(u32, try c_limit.get(req), 10) catch return error.ContractInvalidValue;
    const found = try Conversation.search(p, res.arena, try c_text.get(req), offset, @min(limit, max_limit));
    try res.json(found, .{});
}

const std = @import("std");
const httpz = @import("httpz");
const contract = @import("contract");
const App = @import("../../root.zig").App;
const Conversation = @import("../../../types/root.zig").Conversation;
