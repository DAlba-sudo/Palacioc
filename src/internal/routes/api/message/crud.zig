const c_id = contract.Contract{ .key = "id", .location = .Path };
const c_conversation = contract.Contract{ .key = "conversation_id", .location = .Body };
const c_parent = contract.Contract{ .key = "parent_message_id", .location = .Body };
const c_content = contract.Contract{ .key = "content", .location = .Body };
const c_role = contract.Contract{ .key = "role", .location = .Body };

/// Blank counts as absent, so HTML-style empty fields work.
fn optId(c: contract.Contract, req: *httpz.Request) !?i32 {
    const raw = c.opt(req) orelse return null;
    if (raw.len == 0) return null;
    return contract.parseId(raw) orelse error.ContractInvalidValue;
}

/// POST /api/message: content (required), role (default person) and either
/// parent_message_id (child; the conversation follows the parent) or
/// conversation_id (new root).
pub fn create(app: App, req: *httpz.Request, res: *httpz.Response) !void {
    const p = try app.pool();
    const conversation_id = try optId(c_conversation, req);
    const parent_id = try optId(c_parent, req);
    if (conversation_id == null and parent_id == null) return error.ContractKeyNotFound;
    const content = try validate.content(c_content.opt(req));
    const role = try validate.role(c_role.opt(req));
    const created = try Message.create(p, res.arena, conversation_id, parent_id, role, content) orelse return error.NotFound;
    res.setStatus(.created);
    try res.json(created, .{});
}

pub fn get(app: App, req: *httpz.Request, res: *httpz.Response) !void {
    const found = try Message.get(try app.pool(), res.arena, try c_id.getId(req)) orelse return error.NotFound;
    try res.json(found, .{});
}

/// PUT /api/message/:id: any of content, role.
pub fn update(app: App, req: *httpz.Request, res: *httpz.Response) !void {
    const p = try app.pool();
    const id = try c_id.getId(req);
    const content = try validate.maybe(validate.content, c_content.opt(req));
    const role = try validate.maybe(validate.role, c_role.opt(req));
    const updated = try Message.update(p, res.arena, id, content, role) orelse return error.NotFound;
    try res.json(updated, .{});
}

/// DELETE /api/message/:id: removes the whole subtree and its translations.
pub fn delete(app: App, req: *httpz.Request, res: *httpz.Response) !void {
    const id = try c_id.getId(req);
    if (!try Message.delete(try app.pool(), id)) return error.NotFound;
    try res.json(.{ .deleted = id }, .{});
}

/// GET /api/message/:id/route: the root-to-message path, each with its translations.
pub fn route(app: App, req: *httpz.Request, res: *httpz.Response) !void {
    const p = try app.pool();
    const a = res.arena;
    const path = try Message.route(p, a, try c_id.getId(req));
    if (path.len == 0) return error.NotFound;
    const translations = try Translation.listByConversation(p, a, path[0].conversation_id);
    const out = try a.alloc(Step, path.len);
    for (path, out) |m, *s| {
        var own: std.ArrayList(Translation) = .empty;
        for (translations) |t| if (t.message_id == m.id) try own.append(a, t);
        s.* = .{ .message = m, .translations = own.items };
    }
    try res.json(out, .{});
}

const Step = struct {
    message: Message,
    translations: []const Translation,
};

const std = @import("std");
const httpz = @import("httpz");
const contract = @import("contract");
const App = @import("../../root.zig").App;
const types = @import("../../../types/root.zig");
const validate = types.validate;
const Message = types.Message;
const Translation = types.Translation;
