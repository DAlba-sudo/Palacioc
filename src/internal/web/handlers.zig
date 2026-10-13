//! HTMX handlers. Every page and state change answers with the whole shell
//! (html/shell.zmpl): a plain navigation gets it inside the layout, an htmx
//! request gets the bare shell and the client picks what it needs with
//! `hx-select`/`hx-select-oob`. The conversation state lives in the query
//! string: `sel` (selected message), `leaf` (pinned route end), `edit`, `q`.
//! Errors returned here become flash fragments (routes/errors.zig); invalid
//! forms re-render the shell with status 422.
const c_id = contract.Contract{ .key = "id", .location = .Path };
const c_sel = contract.Contract{ .key = "sel", .location = .Query };
const c_leaf = contract.Contract{ .key = "leaf", .location = .Query };
const b_sel = contract.Contract{ .key = "sel", .location = .Body };
const b_leaf = contract.Contract{ .key = "leaf", .location = .Body };
const c_lang = contract.Contract{ .key = "lang", .location = .Query };
const b_lang = contract.Contract{ .key = "lang", .location = .Body };
const c_via = contract.Contract{ .key = "via", .location = .Query };
const c_cur = contract.Contract{ .key = "cur", .location = .Query };
const c_edit = contract.Contract{ .key = "edit", .location = .Query };
const c_q = contract.Contract{ .key = "q", .location = .Query };

/// Event the composer listens to: clear, focus and scroll the chat down.
const chat_sent = "chat-sent";
/// Event that puts focus back in the translation textarea.
const tr_saved = "tr-saved";

/// Forms to re-render with their errors.
const Extra = struct {
    conv_form: ?forms.ConversationForm = null,
    composer: ?forms.MessageForm = null,
    edit_msg: ?forms.MessageForm = null,
    tr: ?forms.TranslationForm = null,
    notice: []const u8 = "",
};

/// Blank or malformed ids count as absent: stale links must not fail.
fn optId(c: contract.Contract, req: *httpz.Request) ?i32 {
    return contract.parseId(c.opt(req) orelse return null);
}

/// A syntactically valid language code, else "" (source); the view then drops codes without translations.
fn langOf(c: contract.Contract, req: *httpz.Request) []const u8 {
    return validate.language(c.opt(req)) catch "";
}

fn stateOf(req: *httpz.Request, conv: i32) view.State {
    return .{
        .conv = conv,
        .sel = optId(c_sel, req),
        .leaf = optId(c_leaf, req),
        .via = optId(c_via, req),
        .lang = langOf(c_lang, req),
        .edit = view.parseEdit(c_edit.opt(req) orelse ""),
        .q = std.mem.trim(u8, c_q.opt(req) orelse "", " \t\r\n"),
    };
}

fn show(app: App, req: *httpz.Request, res: *httpz.Response, state: view.State, status: std.http.Status, extra: Extra) !void {
    const p = try app.pool();
    const a = res.arena;
    var input: view.Input = .{
        .state = state,
        .cards = try Conversation.search(p, a, state.q, 0, view.max_cards),
        .conv_form = extra.conv_form,
        .composer = extra.composer,
        .edit_msg = extra.edit_msg,
        .tr = extra.tr,
        .notice = extra.notice,
    };
    if (state.conv != 0) {
        const conv = try Conversation.get(p, a, state.conv) orelse return error.NotFound;
        input.conv = conv;
        input.messages = try Message.listByConversation(p, a, conv.id);
        input.translations = try Translation.listByConversation(p, a, conv.id);
    }
    try render.send(app, res, "shell", !render.isFragment(req), status, try view.shell(a, input));
}

fn pushUrl(res: *httpz.Response, conv: i32, sel: ?i32, leaf: ?i32, lang: []const u8) !void {
    res.header("HX-Push-Url", try view.url(res.arena, conv, sel, leaf, .none, lang));
}

// -- conversations ---------------------------------------------------------

/// GET /?q=
pub fn home(app: App, req: *httpz.Request, res: *httpz.Response) !void {
    try show(app, req, res, stateOf(req, 0), .ok, .{});
}

/// GET /ui/conversation/:id?sel=&leaf=&edit=&q=
pub fn conversationPage(app: App, req: *httpz.Request, res: *httpz.Response) !void {
    try show(app, req, res, stateOf(req, try c_id.getId(req)), .ok, .{});
}

/// POST /ui/conversations: redirects to the new conversation, or 422 + form.
pub fn createConversation(app: App, req: *httpz.Request, res: *httpz.Response) !void {
    const p = try app.pool();
    const f = forms.conversation(req.formData() catch return error.ContractKeyNotFound);
    if (!forms.ok(f)) return show(app, req, res, stateOf(req, 0), .unprocessable_entity, .{ .conv_form = f });
    const first: ?[]const u8 = if (f.first_message.len > 0) f.first_message else null;
    const created = try Conversation.create(p, res.arena, f.title, f.description, f.language, first, validate.default_role);
    res.setStatus(.created);
    res.header("HX-Redirect", try std.fmt.allocPrint(res.arena, "/ui/conversation/{d}", .{created.id}));
}

/// DELETE /ui/conversation/:id?cur=<open conversation>: deleting the open one
/// goes home; any other card leaves the open conversation as it is.
pub fn deleteConversation(app: App, req: *httpz.Request, res: *httpz.Response) !void {
    const id = try c_id.getId(req);
    if (!try Conversation.delete(try app.pool(), id)) return error.NotFound;
    const cur = optId(c_cur, req) orelse 0;
    if (cur == id) return res.header("HX-Redirect", "/");
    try show(app, req, res, stateOf(req, cur), .ok, .{});
}

// -- messages --------------------------------------------------------------

/// POST /ui/conversation/:id/messages (form: role, content, sel, leaf): replies to the selected message, else
/// to the route's leaf, else adds a root. The new message becomes leaf and selection.
pub fn messageCreate(app: App, req: *httpz.Request, res: *httpz.Response) !void {
    const p = try app.pool();
    const a = res.arena;
    const conv = try c_id.getId(req);
    // The composer outlives state changes, so its state travels in the form.
    var state = stateOf(req, conv);
    state.sel = optId(b_sel, req);
    state.leaf = optId(b_leaf, req);
    state.lang = langOf(b_lang, req);
    const f = forms.message(req.formData() catch return error.ContractKeyNotFound);
    if (!forms.ok(f)) return show(app, req, res, state, .unprocessable_entity, .{ .composer = f });

    const route = try route_mod.resolve(a, try Message.listByConversation(p, a, conv), .{ .sel = state.sel, .leaf = state.leaf });
    const parent = route.sel orelse route.leaf;
    const created = try Message.create(p, a, conv, parent, f.role, f.content) orelse return error.NotFound;
    try pushUrl(res, conv, created.id, created.id, state.lang);
    res.header("HX-Trigger-After-Settle", chat_sent);
    try show(app, req, res, .{ .conv = conv, .sel = created.id, .leaf = created.id, .lang = state.lang }, .ok, .{});
}

fn messageById(app: App, res: *httpz.Response, id: i32) !types.Message {
    return try Message.get(try app.pool(), res.arena, id) orelse error.NotFound;
}

/// PUT /ui/message/:id?leaf=
pub fn messageUpdate(app: App, req: *httpz.Request, res: *httpz.Response) !void {
    const p = try app.pool();
    const m = try messageById(app, res, try c_id.getId(req));
    var state = stateOf(req, m.conversation_id);
    state.sel = m.id;
    const f = forms.message(req.formData() catch return error.ContractKeyNotFound);
    if (!forms.ok(f)) {
        state.edit = .message;
        return show(app, req, res, state, .unprocessable_entity, .{ .edit_msg = f });
    }
    _ = try Message.update(p, res.arena, m.id, f.content, f.role) orelse return error.NotFound;
    state.edit = .none;
    try show(app, req, res, state, .ok, .{});
}

/// DELETE /ui/message/:id?leaf=: removes the subtree, then shows the route through the parent.
pub fn messageDelete(app: App, req: *httpz.Request, res: *httpz.Response) !void {
    const p = try app.pool();
    const m = try messageById(app, res, try c_id.getId(req));
    if (!try Message.delete(p, m.id)) return error.NotFound;
    var leaf = optId(c_leaf, req);
    if (leaf) |l| {
        if (try Message.get(p, res.arena, l) == null) leaf = null;
    }
    try pushUrl(res, m.conversation_id, m.parent_message_id, leaf, langOf(c_lang, req));
    try show(app, req, res, .{ .conv = m.conversation_id, .sel = m.parent_message_id, .leaf = leaf, .lang = langOf(c_lang, req) }, .ok, .{});
}

// -- translations ----------------------------------------------------------

/// POST /ui/message/:id/translations?sel=&leaf=
pub fn translationCreate(app: App, req: *httpz.Request, res: *httpz.Response) !void {
    const p = try app.pool();
    const m = try messageById(app, res, try c_id.getId(req));
    var state = stateOf(req, m.conversation_id);
    state.sel = m.id;
    const f = forms.translation(req.formData() catch return error.ContractKeyNotFound);
    if (!forms.ok(f)) return show(app, req, res, state, .unprocessable_entity, .{ .tr = f });
    _ = try Translation.create(p, res.arena, m.id, f.language, f.content) orelse return error.NotFound;
    res.header("HX-Trigger-After-Settle", tr_saved);
    try show(app, req, res, state, .ok, .{ .notice = "Added" });
}

fn translationAndMessage(app: App, res: *httpz.Response, id: i32) !struct { types.Translation, types.Message } {
    const t = try Translation.get(try app.pool(), res.arena, id) orelse return error.NotFound;
    return .{ t, try messageById(app, res, t.message_id) };
}

/// PUT /ui/translation/:id?sel=&leaf=
pub fn translationUpdate(app: App, req: *httpz.Request, res: *httpz.Response) !void {
    const t, const m = try translationAndMessage(app, res, try c_id.getId(req));
    var state = stateOf(req, m.conversation_id);
    state.sel = m.id;
    const f = forms.translation(req.formData() catch return error.ContractKeyNotFound);
    if (!forms.ok(f)) {
        state.edit = .{ .translation = t.id };
        return show(app, req, res, state, .unprocessable_entity, .{ .tr = f });
    }
    _ = try Translation.update(try app.pool(), res.arena, t.id, f.language, f.content) orelse return error.NotFound;
    state.edit = .none;
    res.header("HX-Trigger-After-Settle", tr_saved);
    try show(app, req, res, state, .ok, .{ .notice = "Saved" });
}

/// DELETE /ui/translation/:id?sel=&leaf=
pub fn translationDelete(app: App, req: *httpz.Request, res: *httpz.Response) !void {
    const t, const m = try translationAndMessage(app, res, try c_id.getId(req));
    if (!try Translation.delete(try app.pool(), t.id)) return error.NotFound;
    var state = stateOf(req, m.conversation_id);
    state.sel = m.id;
    state.edit = .none;
    try show(app, req, res, state, .ok, .{});
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
const route_mod = @import("route.zig");
