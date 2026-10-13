const c_id = contract.Contract{ .key = "id", .location = .Path };
const c_title = contract.Contract{ .key = "title", .location = .Body };
const c_description = contract.Contract{ .key = "description", .location = .Body };
const c_language = contract.Contract{ .key = "source_language", .location = .Body };
const c_first = contract.Contract{ .key = "initial_message", .location = .Body };
const c_first_role = contract.Contract{ .key = "initial_message_role", .location = .Body };

/// POST /api/conversation: title (required), description, source_language
/// (default en), initial_message + initial_message_role (a root message).
pub fn create(app: App, req: *httpz.Request, res: *httpz.Response) !void {
    const p = try app.pool();
    const title = try validate.title(c_title.opt(req));
    const description = try validate.description(c_description.opt(req));
    const language = try validate.languageOrDefault(c_language.opt(req));
    const role = try validate.role(c_first_role.opt(req));
    const first = try validate.maybe(validate.content, c_first.opt(req));
    const created = try Conversation.create(p, res.arena, title, description, language, first, role);
    res.setStatus(.created);
    try res.json(created, .{});
}

pub fn get(app: App, req: *httpz.Request, res: *httpz.Response) !void {
    const found = try Conversation.get(try app.pool(), res.arena, try c_id.getId(req)) orelse return error.NotFound;
    try res.json(found, .{});
}

/// PUT /api/conversation/:id: any of title, description, source_language.
pub fn update(app: App, req: *httpz.Request, res: *httpz.Response) !void {
    const p = try app.pool();
    const id = try c_id.getId(req);
    const title = try validate.maybe(validate.title, c_title.opt(req));
    const description = try validate.maybe(validate.description, c_description.opt(req));
    const language = try validate.maybe(validate.language, c_language.opt(req));
    const updated = try Conversation.update(p, res.arena, id, title, description, language) orelse return error.NotFound;
    try res.json(updated, .{});
}

/// DELETE /api/conversation/:id (cascades to messages and translations).
pub fn delete(app: App, req: *httpz.Request, res: *httpz.Response) !void {
    const id = try c_id.getId(req);
    if (!try Conversation.delete(try app.pool(), id)) return error.NotFound;
    try res.json(.{ .deleted = id }, .{});
}

/// GET /api/conversation/:id/tree: `{conversation, messages}`; each message
/// carries `parent_message_id` (null = root) and its `translations`, in id
/// order (a parent always precedes its children).
pub fn tree(app: App, req: *httpz.Request, res: *httpz.Response) !void {
    const p = try app.pool();
    const a = res.arena;
    const conversation = try Conversation.get(p, a, try c_id.getId(req)) orelse return error.NotFound;
    const messages = try Message.listByConversation(p, a, conversation.id);
    const translations = try Translation.listByConversation(p, a, conversation.id);
    // Flat, not nested: std.json overflows its bit stack on deep chains.
    const flat = try types.tree.flat(a, messages, translations);
    try res.json(.{ .conversation = conversation, .messages = flat }, .{});
}

const httpz = @import("httpz");
const contract = @import("contract");
const App = @import("../../root.zig").App;
const types = @import("../../../types/root.zig");
const validate = types.validate;
const Conversation = types.Conversation;
const Message = types.Message;
const Translation = types.Translation;
