//! View model of the two-pane shell (html/shell.zmpl) and its builder. Every
//! field is preformatted for printing; the builder is pure (no DB, no HTTP) and
//! allocates in the request arena. "" means unset for strings.
pub const max_cards = 48;
const snippet_len = 60;

/// Which edit form the work pane shows instead of the plain translation form.
pub const Edit = union(enum) { none, message, translation: i32 };

/// The request state carried in `/ui/conversation/:id?sel=&leaf=&edit=&q=`.
pub const State = struct {
    conv: i32 = 0,
    sel: ?i32 = null,
    leaf: ?i32 = null,
    edit: Edit = .none,
    q: []const u8 = "",
};

/// "m" (the selected message) or "t<id>" (a translation); anything else is none.
pub fn parseEdit(s: []const u8) Edit {
    if (std.mem.eql(u8, s, "m")) return .message;
    if (s.len > 1 and s[0] == 't') {
        if (contract.parseId(s[1..])) |id| return .{ .translation = id };
    }
    return .none;
}

/// `/ui/conversation/<conv>` with `sel`, `leaf` and `edit` as query params when set.
pub fn url(a: std.mem.Allocator, conv: i32, sel: ?i32, leaf: ?i32, edit: Edit) ![]const u8 {
    var aw: std.Io.Writer.Allocating = .init(a);
    const w = &aw.writer;
    try w.print("/ui/conversation/{d}", .{conv});
    var sep: u8 = '?';
    if (sel) |s| {
        try w.print("{c}sel={d}", .{ sep, s });
        sep = '&';
    }
    if (leaf) |l| {
        try w.print("{c}leaf={d}", .{ sep, l });
        sep = '&';
    }
    switch (edit) {
        .none => {},
        .message => try w.print("{c}edit=m", .{sep}),
        .translation => |t| try w.print("{c}edit=t{d}", .{ sep, t }),
    }
    return aw.written();
}

/// `?sel=..&leaf=..` for the mutation endpoints ("" when both are unset).
pub fn stateQuery(a: std.mem.Allocator, sel: ?i32, leaf: ?i32) ![]const u8 {
    if (sel) |s| {
        if (leaf) |l| return std.fmt.allocPrint(a, "?sel={d}&leaf={d}", .{ s, l });
        return std.fmt.allocPrint(a, "?sel={d}", .{s});
    }
    if (leaf) |l| return std.fmt.allocPrint(a, "?leaf={d}", .{l});
    return "";
}

pub const RoleOpt = struct { name: []const u8 };

/// Distinct roles used in the conversation, most recently used first, always
/// ending with the default role when it has not been used.
pub fn roleSuggestions(a: std.mem.Allocator, messages: []const types.Message) ![]const RoleOpt {
    var out: std.ArrayList(RoleOpt) = .empty;
    var i = messages.len;
    while (i > 0) {
        i -= 1;
        try addRole(a, &out, messages[i].role);
    }
    try addRole(a, &out, validate.default_role);
    return out.items;
}

fn addRole(a: std.mem.Allocator, out: *std.ArrayList(RoleOpt), role: []const u8) !void {
    for (out.items) |r| if (std.mem.eql(u8, r.name, role)) return;
    try out.append(a, .{ .name = role });
}

/// At most `snippet_len` code points, with an ellipsis when cut.
fn snippet(a: std.mem.Allocator, s: []const u8) ![]const u8 {
    var it = (std.unicode.Utf8View.init(s) catch return "").iterator();
    var n: usize = 0;
    while (it.nextCodepointSlice()) |_| {
        if (n == snippet_len) return std.fmt.allocPrint(a, "{s}...", .{s[0..it.i]});
        n += 1;
    }
    return s;
}

pub const Bubble = struct {
    id: i32,
    role: []const u8,
    content: []const u8,
    cls: []const u8,
    current: []const u8,
    select_url: []const u8,
    edit_url: []const u8,
    delete_url: []const u8,
    /// "1/3"; the switcher carries `hidden` when the message has no siblings.
    sw_label: []const u8,
    sw_hidden: []const u8,
    prev_url: []const u8,
    next_url: []const u8,
    prev_attr: []const u8,
    next_attr: []const u8,
    /// "2 translations", or "".
    note: []const u8,
};

pub const Card = struct {
    id: i32,
    title: []const u8,
    description: []const u8,
    language: []const u8,
    cls: []const u8,
    open_url: []const u8,
    delete_url: []const u8,
};

pub const TrRow = struct { id: i32, language: []const u8, content: []const u8, edit_url: []const u8, delete_url: []const u8 };

pub const Shell = struct {
    // Chat pane.
    has_conv: bool,
    bubbles: []const Bubble,
    empty_chat: bool,
    empty_text: []const u8,
    composer_action: []const u8,
    /// Hidden form values, so the persistent composer always posts the current state.
    composer_sel: []const u8,
    composer_leaf: []const u8,
    composer_role: []const u8,
    composer_err: []const u8,
    composer_disabled: []const u8,
    roles: []const RoleOpt,
    chip: bool,
    chip_text: []const u8,
    chip_clear_url: []const u8,

    // Work pane modes (exactly one is true).
    mode_cards: bool,
    mode_translate: bool,
    mode_edit_msg: bool,

    // Conversations mode.
    q: []const u8,
    search_url: []const u8,
    cards: []const Card,
    cards_empty: bool,
    form: forms.ConversationForm,
    new_open: []const u8,

    // Translation mode (also holds the edit-translation form).
    back_url: []const u8,
    cancel_url: []const u8,
    sel_role: []const u8,
    sel_content: []const u8,
    tr_edit: bool,
    tr_action: []const u8,
    tr_heading: []const u8,
    tr_button: []const u8,
    tr_language: []const u8,
    tr_content: []const u8,
    err_tr_language: []const u8,
    err_tr_content: []const u8,
    trs: []const TrRow,
    trs_empty: bool,

    // Edit-message mode.
    em_action: []const u8,
    em_role: []const u8,
    em_content: []const u8,
    err_em_role: []const u8,
    err_em_content: []const u8,
};

pub const Input = struct {
    state: State,
    /// Null on the home page (no conversation open).
    conv: ?types.Conversation = null,
    messages: []const types.Message = &.{},
    translations: []const types.Translation = &.{},
    cards: []const types.Conversation = &.{},
    /// Re-rendered forms (validation errors and echoed input).
    conv_form: ?forms.ConversationForm = null,
    composer: ?forms.MessageForm = null,
    edit_msg: ?forms.MessageForm = null,
    tr: ?forms.TranslationForm = null,
};

pub fn shell(a: std.mem.Allocator, in: Input) !Shell {
    const conv_id: i32 = if (in.conv) |c| c.id else 0;
    const route = try route_mod.resolve(a, in.messages, in.state.sel, in.state.leaf);
    const sel = route.sel;
    const leaf = route.leaf;

    const bubbles = try a.alloc(Bubble, route.steps.len);
    for (route.steps, bubbles) |s, *b| {
        const m = in.messages[s.index];
        var n: usize = 0;
        for (in.translations) |t| {
            if (t.message_id == m.id) n += 1;
        }
        const selected = sel != null and sel.? == m.id;
        b.* = .{
            .id = m.id,
            .role = m.role,
            .content = m.content,
            .cls = if (selected) "bubble sel" else "bubble",
            .current = if (selected) "true" else "false",
            .select_url = try url(a, conv_id, m.id, leaf, .none),
            .edit_url = try url(a, conv_id, m.id, leaf, .message),
            .delete_url = try std.fmt.allocPrint(a, "/ui/message/{d}{s}", .{ m.id, try stateQuery(a, null, leaf) }),
            .sw_label = try std.fmt.allocPrint(a, "{d}/{d}", .{ s.pos, s.count }),
            .sw_hidden = if (s.count > 1) "" else "hidden",
            .prev_url = if (s.prev) |p| try url(a, conv_id, p, null, .none) else "",
            .next_url = if (s.next) |nx| try url(a, conv_id, nx, null, .none) else "",
            .prev_attr = if (s.prev == null) "disabled" else "",
            .next_attr = if (s.next == null) "disabled" else "",
            .note = switch (n) {
                0 => "",
                1 => "1 translation",
                else => try std.fmt.allocPrint(a, "{d} translations", .{n}),
            },
        };
    }

    var leaf_role: []const u8 = validate.default_role;
    var sel_msg: ?types.Message = null;
    for (in.messages) |m| {
        if (leaf != null and m.id == leaf.?) leaf_role = m.role;
        if (sel != null and m.id == sel.?) sel_msg = m;
    }

    // Translations of the selected message; the most recent one in the conversation seeds the language.
    var trs: std.ArrayList(TrRow) = .empty;
    var latest: ?types.Translation = null;
    var editing: ?types.Translation = null;
    for (in.translations) |t| {
        latest = t; // ascending id
        if (sel_msg) |sm| {
            if (t.message_id != sm.id) continue;
            const edit_here = in.state.edit == .translation and in.state.edit.translation == t.id;
            if (edit_here) editing = t;
            try trs.append(a, .{
                .id = t.id,
                .language = t.language,
                .content = t.content,
                .edit_url = try url(a, conv_id, sm.id, leaf, .{ .translation = t.id }),
                .delete_url = try std.fmt.allocPrint(a, "/ui/translation/{d}{s}", .{ t.id, try stateQuery(a, sm.id, leaf) }),
            });
        }
    }

    const edit_msg_mode = sel_msg != null and in.state.edit == .message;
    const translate_mode = sel_msg != null and !edit_msg_mode;
    const sm_id: i32 = if (sel_msg) |m| m.id else 0;
    const q_sel = try stateQuery(a, sel, leaf);

    const tr_in = in.tr orelse forms.TranslationForm{
        .language = if (editing) |e| e.language else if (latest) |l| l.language else "",
        .content = if (editing) |e| e.content else "",
    };
    const em_in = in.edit_msg orelse forms.MessageForm{
        .role = if (sel_msg) |m| m.role else "",
        .content = if (sel_msg) |m| m.content else "",
    };
    const composer = in.composer orelse forms.MessageForm{ .role = leaf_role };

    const cards = try a.alloc(Card, in.cards.len);
    for (in.cards, cards) |c, *o| {
        o.* = .{
            .id = c.id,
            .title = c.title,
            .description = c.description,
            .language = c.source_language,
            .cls = if (c.id == conv_id) "card sel" else "card",
            .open_url = try std.fmt.allocPrint(a, "/ui/conversation/{d}", .{c.id}),
            .delete_url = try std.fmt.allocPrint(a, "/ui/conversation/{d}", .{c.id}),
        };
    }

    return .{
        .has_conv = in.conv != null,
        .bubbles = bubbles,
        .empty_chat = bubbles.len == 0,
        .empty_text = if (in.conv != null) "No messages yet. Write the first one below." else "Open a conversation to start.",
        .composer_action = if (in.conv != null) try std.fmt.allocPrint(a, "/ui/conversation/{d}/messages", .{conv_id}) else "",
        .composer_sel = if (sel) |s| try std.fmt.allocPrint(a, "{d}", .{s}) else "",
        .composer_leaf = if (leaf) |l| try std.fmt.allocPrint(a, "{d}", .{l}) else "",
        .composer_role = composer.role,
        .composer_err = if (composer.err_content.len > 0) composer.err_content else composer.err_role,
        .composer_disabled = if (in.conv != null) "" else "disabled",
        .roles = try roleSuggestions(a, in.messages),
        .chip = sel_msg != null,
        .chip_text = if (sel_msg) |m| try snippet(a, m.content) else "",
        .chip_clear_url = try url(a, conv_id, null, leaf, .none),

        .mode_cards = sel_msg == null,
        .mode_translate = translate_mode,
        .mode_edit_msg = edit_msg_mode,

        .q = in.state.q,
        .search_url = if (in.conv != null) try url(a, conv_id, null, leaf, .none) else "/",
        .cards = cards,
        .cards_empty = cards.len == 0,
        .form = in.conv_form orelse .{ .language = validate.default_language },
        .new_open = if (in.conv_form != null) "open" else "",

        .back_url = if (in.conv != null) try url(a, conv_id, null, leaf, .none) else "/",
        .cancel_url = try url(a, conv_id, sel, leaf, .none),
        .sel_role = if (sel_msg) |m| m.role else "",
        .sel_content = if (sel_msg) |m| m.content else "",
        .tr_edit = editing != null,
        .tr_action = if (editing) |e|
            try std.fmt.allocPrint(a, "/ui/translation/{d}{s}", .{ e.id, q_sel })
        else
            try std.fmt.allocPrint(a, "/ui/message/{d}/translations{s}", .{ sm_id, q_sel }),
        .tr_heading = if (editing != null) "Edit translation" else "Translation",
        .tr_button = if (editing != null) "Save" else "Translate",
        .tr_language = tr_in.language,
        .tr_content = tr_in.content,
        .err_tr_language = tr_in.err_language,
        .err_tr_content = tr_in.err_content,
        .trs = trs.items,
        .trs_empty = trs.items.len == 0,

        .em_action = try std.fmt.allocPrint(a, "/ui/message/{d}{s}", .{ sm_id, try stateQuery(a, null, leaf) }),
        .em_role = em_in.role,
        .em_content = em_in.content,
        .err_em_role = em_in.err_role,
        .err_em_content = em_in.err_content,
    };
}

const std = @import("std");
const contract = @import("contract");
const types = @import("../types/root.zig");
const validate = types.validate;
const forms = @import("forms.zig");
const route_mod = @import("route.zig");

fn msg(id: i32, parent: ?i32, role: []const u8) types.Message {
    return .{ .id = id, .conversation_id = 1, .parent_message_id = parent, .role = role, .content = "c", .created_at = 0, .updated_at = 0 };
}

test "roleSuggestions: most recent first, deduplicated, person last when unused" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ms = [_]types.Message{ msg(1, null, "waiter"), msg(2, 1, "guest"), msg(3, 2, "waiter") };
    const got = try roleSuggestions(a, &ms);
    try std.testing.expectEqual(@as(usize, 3), got.len);
    try std.testing.expectEqualStrings("waiter", got[0].name);
    try std.testing.expectEqualStrings("guest", got[1].name);
    try std.testing.expectEqualStrings("person", got[2].name);

    const used = try roleSuggestions(a, &[_]types.Message{ msg(1, null, "person"), msg(2, 1, "guest") });
    try std.testing.expectEqualStrings("guest", used[0].name);
    try std.testing.expectEqual(@as(usize, 2), used.len);
    try std.testing.expectEqualStrings("person", (try roleSuggestions(a, &.{}))[0].name);
}

test "urls and edit parsing" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqualStrings("/ui/conversation/3", try url(a, 3, null, null, .none));
    try std.testing.expectEqualStrings("/ui/conversation/3?sel=4&leaf=9&edit=t5", try url(a, 3, 4, 9, .{ .translation = 5 }));
    try std.testing.expectEqualStrings("/ui/conversation/3?leaf=9&edit=m", try url(a, 3, null, 9, .message));
    try std.testing.expectEqualStrings("?leaf=9", try stateQuery(a, null, 9));
    try std.testing.expectEqual(Edit.message, parseEdit("m"));
    try std.testing.expectEqual(@as(i32, 12), parseEdit("t12").translation);
    try std.testing.expectEqual(Edit.none, parseEdit("t0"));
    try std.testing.expectEqual(Edit.none, parseEdit("x"));
}

test "shell: route bubbles, switcher, modes, language seed" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const conv: types.Conversation = .{ .id = 1, .title = "T", .description = "", .source_language = "en", .created_at = 0, .updated_at = 0 };
    const ms = [_]types.Message{ msg(1, null, "a"), msg(2, 1, "b"), msg(3, 1, "c") };
    const trs = [_]types.Translation{
        .{ .id = 1, .message_id = 1, .language = "es", .content = "x", .created_at = 0, .updated_at = 0 },
        .{ .id = 2, .message_id = 2, .language = "fr", .content = "y", .created_at = 0, .updated_at = 0 },
    };

    const home = try shell(a, .{ .state = .{}, .conv = conv, .messages = &ms, .translations = &trs, .cards = &.{conv} });
    try std.testing.expect(home.mode_cards and !home.mode_translate);
    try std.testing.expectEqual(@as(usize, 2), home.bubbles.len);
    try std.testing.expectEqualStrings("1/2", home.bubbles[1].sw_label);
    try std.testing.expectEqualStrings("", home.bubbles[1].sw_hidden);
    try std.testing.expectEqualStrings("hidden", home.bubbles[0].sw_hidden);
    try std.testing.expectEqualStrings("disabled", home.bubbles[1].prev_attr);
    try std.testing.expectEqualStrings("/ui/conversation/1?sel=3", home.bubbles[1].next_url);
    try std.testing.expectEqualStrings("b", home.composer_role);
    try std.testing.expectEqualStrings("card sel", home.cards[0].cls);

    const picked = try shell(a, .{ .state = .{ .sel = 1, .leaf = 2 }, .conv = conv, .messages = &ms, .translations = &trs });
    try std.testing.expect(picked.mode_translate and picked.chip);
    try std.testing.expectEqualStrings("bubble sel", picked.bubbles[0].cls);
    try std.testing.expectEqualStrings("fr", picked.tr_language); // latest translation in the conversation
    try std.testing.expectEqual(@as(usize, 1), picked.trs.len);
    try std.testing.expectEqualStrings("/ui/conversation/1/messages", picked.composer_action);

    const editing = try shell(a, .{ .state = .{ .sel = 1, .leaf = 2, .edit = .{ .translation = 1 } }, .conv = conv, .messages = &ms, .translations = &trs });
    try std.testing.expect(editing.tr_edit);
    try std.testing.expectEqualStrings("es", editing.tr_language);
    const em = try shell(a, .{ .state = .{ .sel = 2, .leaf = 2, .edit = .message }, .conv = conv, .messages = &ms });
    try std.testing.expect(em.mode_edit_msg and !em.mode_translate);

    const none = try shell(a, .{ .state = .{} });
    try std.testing.expectEqualStrings("disabled", none.composer_disabled);
    try std.testing.expect(none.empty_chat and none.mode_cards);
}
