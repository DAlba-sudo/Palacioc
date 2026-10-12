//! HTMX handlers. `/` and `/ui/conversation/:id` are pages (full layout unless
//! the request is an htmx fragment request); the rest answer fragments for
//! `#main`, `#tree` or `#panel`. Errors returned here become flash fragments
//! (see routes/errors.zig); invalid forms are re-rendered with status 422.
const c_id = contract.Contract{ .key = "id", .location = .Path };
const c_q = contract.Contract{ .key = "q", .location = .Query, .default_value = "" };
const c_offset = contract.Contract{ .key = "p", .location = .Query, .default_value = "0" };
const c_conversation = contract.Contract{ .key = "conversation_id", .location = .Query };
const c_parent = contract.Contract{ .key = "parent_id", .location = .Query };
const c_message = contract.Contract{ .key = "message_id", .location = .Query };

/// Tells every `#tree` on the page to reload.
const tree_changed = "tree-changed";

// -- conversations ---------------------------------------------------------

/// GET /: the home page (search + create + list).
pub fn home(app: App, req: *httpz.Request, res: *httpz.Response) !void {
    const p = try app.pool();
    const q = std.mem.trim(u8, try c_q.get(req), " \t\r\n");
    const page = try view.convList(res.arena, q, 0, try Conversation.search(p, res.arena, q, 0, view.page_size + 1));
    try render.send(app, res, "home", !render.isFragment(req), .ok, .{ .list = page, .form = forms.ConversationForm{ .language = validate.default_language } });
}

/// GET /ui/conversations?q=&p=: one page of list items (appended by "more").
pub fn list(app: App, req: *httpz.Request, res: *httpz.Response) !void {
    if (!render.isFragment(req)) return home(app, req, res);
    const p = try app.pool();
    const q = std.mem.trim(u8, try c_q.get(req), " \t\r\n");
    const offset = std.fmt.parseInt(u32, try c_offset.get(req), 10) catch return error.ContractInvalidValue;
    const found = try Conversation.search(p, res.arena, q, offset, view.page_size + 1);
    try render.send(app, res, "list_fragment", false, .ok, .{ .list = try view.convList(res.arena, q, offset, found) });
}

/// POST /ui/conversations: redirects to the new conversation, or 422 + form.
pub fn createConversation(app: App, req: *httpz.Request, res: *httpz.Response) !void {
    const p = try app.pool();
    const f = forms.conversation(req.formData() catch return error.ContractKeyNotFound);
    if (!forms.ok(f)) return render.send(app, res, "conversation_form", false, .unprocessable_entity, .{ .form = f });
    const first: ?[]const u8 = if (f.first_message.len > 0) f.first_message else null;
    const created = try Conversation.create(p, res.arena, f.title, f.description, f.language, first, validate.default_role);
    res.setStatus(.created);
    res.header("HX-Redirect", try std.fmt.allocPrint(res.arena, "/ui/conversation/{d}", .{created.id}));
}

fn treePage(app: App, req: *httpz.Request, res: *httpz.Response) !view.TreePage {
    const p = try app.pool();
    const a = res.arena;
    const conv = try Conversation.get(p, a, try c_id.getId(req)) orelse return error.NotFound;
    const messages = try Message.listByConversation(p, a, conv.id);
    const translations = try Translation.listByConversation(p, a, conv.id);
    const rows = try view.rows(a, try types.tree.build(a, messages, translations));
    return .{ .conv = view.convItem(conv), .rows = rows, .empty = rows.len == 0 };
}

/// GET /ui/conversation/:id
pub fn conversationPage(app: App, req: *httpz.Request, res: *httpz.Response) !void {
    try render.send(app, res, "conversation_page", !render.isFragment(req), .ok, .{ .page = try treePage(app, req, res) });
}

/// GET /ui/conversation/:id/tree: just the tree (reloaded on `tree-changed`).
pub fn tree(app: App, req: *httpz.Request, res: *httpz.Response) !void {
    try render.send(app, res, "tree_fragment", false, .ok, .{ .page = try treePage(app, req, res) });
}

/// DELETE /ui/conversation/:id
pub fn deleteConversation(app: App, req: *httpz.Request, res: *httpz.Response) !void {
    if (!try Conversation.delete(try app.pool(), try c_id.getId(req))) return error.NotFound;
    res.header("HX-Redirect", "/");
}

// -- messages --------------------------------------------------------------

/// The action panel of a message; `status` is 200 except for re-renders.
fn menu(app: App, res: *httpz.Response, m: types.Message) !void {
    try render.send(app, res, "message_menu", false, .ok, .{ .msg = view.msgView(m) });
}

fn messageById(app: App, res: *httpz.Response, id: i32) !types.Message {
    return try Message.get(try app.pool(), res.arena, id) orelse error.NotFound;
}

/// GET /ui/message/:id/menu
pub fn messageMenu(app: App, req: *httpz.Request, res: *httpz.Response) !void {
    try menu(app, res, try messageById(app, res, try c_id.getId(req)));
}

/// GET /ui/message/:id/route
pub fn messageRoute(app: App, req: *httpz.Request, res: *httpz.Response) !void {
    const p = try app.pool();
    const a = res.arena;
    const path = try Message.route(p, a, try c_id.getId(req));
    if (path.len == 0) return error.NotFound;
    const translations = try Translation.listByConversation(p, a, path[0].conversation_id);
    try render.send(app, res, "route_panel", false, .ok, .{ .msg = view.msgView(path[path.len - 1]), .steps = try view.routeRows(a, path, translations) });
}

/// GET /ui/message/new?parent_id= (child, new branch) or ?conversation_id= (new root)
pub fn messageNew(app: App, req: *httpz.Request, res: *httpz.Response) !void {
    var f: forms.MessageForm = .{};
    var hint: []const u8 = "New root message";
    if (c_parent.opt(req)) |raw| {
        const parent = try messageById(app, res, contract.parseId(raw) orelse return error.ContractInvalidValue);
        f.parent_id = parent.id;
        hint = parent.content;
    } else {
        f.conversation_id = try c_conversation.getId(req);
    }
    try render.send(app, res, "message_form", false, .ok, .{ .form = view.messageForm(f, false, 0, hint) });
}

/// POST /ui/message
pub fn messageCreate(app: App, req: *httpz.Request, res: *httpz.Response) !void {
    const p = try app.pool();
    const f = forms.message(req.formData() catch return error.ContractKeyNotFound);
    if (!forms.ok(f)) {
        var hint: []const u8 = "New root message";
        if (f.parent_id != 0) hint = (try messageById(app, res, f.parent_id)).content;
        return render.send(app, res, "message_form", false, .unprocessable_entity, .{ .form = view.messageForm(f, false, 0, hint) });
    }
    if (f.parent_id == 0 and f.conversation_id == 0) return error.ContractKeyNotFound;
    const parent: ?i32 = if (f.parent_id != 0) f.parent_id else null;
    const conversation: ?i32 = if (f.conversation_id != 0) f.conversation_id else null;
    const created = try Message.create(p, res.arena, conversation, parent, f.role, f.content) orelse return error.NotFound;
    res.header("HX-Trigger", tree_changed);
    try menu(app, res, created);
}

/// GET /ui/message/:id/edit
pub fn messageEdit(app: App, req: *httpz.Request, res: *httpz.Response) !void {
    const m = try messageById(app, res, try c_id.getId(req));
    const f: forms.MessageForm = .{ .role = m.role, .content = m.content };
    try render.send(app, res, "message_form", false, .ok, .{ .form = view.messageForm(f, true, m.id, "") });
}

/// PUT /ui/message/:id
pub fn messageUpdate(app: App, req: *httpz.Request, res: *httpz.Response) !void {
    const p = try app.pool();
    const id = try c_id.getId(req);
    const f = forms.message(req.formData() catch return error.ContractKeyNotFound);
    if (!forms.ok(f)) {
        return render.send(app, res, "message_form", false, .unprocessable_entity, .{ .form = view.messageForm(f, true, id, "") });
    }
    const updated = try Message.update(p, res.arena, id, f.content, f.role) orelse return error.NotFound;
    res.header("HX-Trigger", tree_changed);
    try menu(app, res, updated);
}

/// DELETE /ui/message/:id: the subtree goes too; the panel is emptied.
pub fn messageDelete(app: App, req: *httpz.Request, res: *httpz.Response) !void {
    if (!try Message.delete(try app.pool(), try c_id.getId(req))) return error.NotFound;
    res.header("HX-Trigger", tree_changed);
}

/// GET /ui/panel/close: an empty body empties `#panel`.
pub fn panelClose(_: App, _: *httpz.Request, _: *httpz.Response) !void {}

// -- translations ----------------------------------------------------------

/// GET /ui/translation/new?message_id=
pub fn translationNew(app: App, req: *httpz.Request, res: *httpz.Response) !void {
    const m = try messageById(app, res, try c_message.getId(req));
    const f: forms.TranslationForm = .{};
    try render.send(app, res, "translation_form", false, .ok, .{ .form = view.translationForm(f, false, 0, m.id, m.content) });
}

/// POST /ui/translation
pub fn translationCreate(app: App, req: *httpz.Request, res: *httpz.Response) !void {
    const p = try app.pool();
    const f = forms.translation(req.formData() catch return error.ContractKeyNotFound);
    if (f.message_id == 0) return error.ContractKeyNotFound;
    const m = try messageById(app, res, f.message_id);
    if (!forms.ok(f)) {
        return render.send(app, res, "translation_form", false, .unprocessable_entity, .{ .form = view.translationForm(f, false, 0, m.id, m.content) });
    }
    _ = try Translation.create(p, res.arena, m.id, f.language, f.content) orelse return error.NotFound;
    res.header("HX-Trigger", tree_changed);
    try menu(app, res, m);
}

/// GET /ui/translation/:id/edit
pub fn translationEdit(app: App, req: *httpz.Request, res: *httpz.Response) !void {
    const p = try app.pool();
    const t = try Translation.get(p, res.arena, try c_id.getId(req)) orelse return error.NotFound;
    const m = try messageById(app, res, t.message_id);
    const f: forms.TranslationForm = .{ .language = t.language, .content = t.content };
    try render.send(app, res, "translation_form", false, .ok, .{ .form = view.translationForm(f, true, t.id, m.id, m.content) });
}

/// PUT /ui/translation/:id
pub fn translationUpdate(app: App, req: *httpz.Request, res: *httpz.Response) !void {
    const p = try app.pool();
    const id = try c_id.getId(req);
    const f = forms.translation(req.formData() catch return error.ContractKeyNotFound);
    const current = try Translation.get(p, res.arena, id) orelse return error.NotFound;
    const m = try messageById(app, res, current.message_id);
    if (!forms.ok(f)) {
        return render.send(app, res, "translation_form", false, .unprocessable_entity, .{ .form = view.translationForm(f, true, id, m.id, m.content) });
    }
    _ = try Translation.update(p, res.arena, id, f.language, f.content) orelse return error.NotFound;
    res.header("HX-Trigger", tree_changed);
    try menu(app, res, m);
}

/// DELETE /ui/translation/:id
pub fn translationDelete(app: App, req: *httpz.Request, res: *httpz.Response) !void {
    const p = try app.pool();
    const id = try c_id.getId(req);
    const t = try Translation.get(p, res.arena, id) orelse return error.NotFound;
    if (!try Translation.delete(p, id)) return error.NotFound;
    res.header("HX-Trigger", tree_changed);
    try menu(app, res, try messageById(app, res, t.message_id));
}

const std = @import("std");
const httpz = @import("httpz");
const contract = @import("contract");
const App = @import("../routes/root.zig").App;
const types = @import("../types/root.zig");
const validate = types.validate;
const Conversation = types.Conversation;
const Message = types.Message;
const Translation = types.Translation;
const forms = @import("forms.zig");
const render = @import("render.zig");
const view = @import("view.zig");
