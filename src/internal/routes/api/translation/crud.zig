const c_id = contract.Contract{ .key = "id", .location = .Path };
const c_message = contract.Contract{ .key = "message_id", .location = .Body };
const c_language = contract.Contract{ .key = "language", .location = .Body };
const c_content = contract.Contract{ .key = "content", .location = .Body };

/// POST /api/translation: message_id, language, content.
pub fn create(app: App, req: *httpz.Request, res: *httpz.Response) !void {
    const p = try app.pool();
    const message_id = contract.parseId(try c_message.get(req)) orelse return error.ContractInvalidValue;
    const language = try validate.language(c_language.opt(req));
    const content = try validate.content(c_content.opt(req));
    const created = try Translation.create(p, res.arena, message_id, language, content) orelse return error.NotFound;
    res.setStatus(.created);
    try res.json(created, .{});
}

/// GET /api/message/:id/translations
pub fn listByMessage(app: App, req: *httpz.Request, res: *httpz.Response) !void {
    const p = try app.pool();
    const id = try c_id.getId(req);
    if (try Message.get(p, res.arena, id) == null) return error.NotFound;
    try res.json(try Translation.listByMessage(p, res.arena, id), .{});
}

/// PUT /api/translation/:id: any of language, content.
pub fn update(app: App, req: *httpz.Request, res: *httpz.Response) !void {
    const p = try app.pool();
    const id = try c_id.getId(req);
    const language = try validate.maybe(validate.language, c_language.opt(req));
    const content = try validate.maybe(validate.content, c_content.opt(req));
    const updated = try Translation.update(p, res.arena, id, language, content) orelse return error.NotFound;
    try res.json(updated, .{});
}

pub fn delete(app: App, req: *httpz.Request, res: *httpz.Response) !void {
    const id = try c_id.getId(req);
    if (!try Translation.delete(try app.pool(), id)) return error.NotFound;
    try res.json(.{ .deleted = id }, .{});
}

const httpz = @import("httpz");
const contract = @import("contract");
const App = @import("../../root.zig").App;
const types = @import("../../../types/root.zig");
const validate = types.validate;
const Message = types.Message;
const Translation = types.Translation;
