//! View models and builders. Everything is preformatted so the templates only
//! print; allocations go to the request arena.
pub const page_size = 10;
/// Deeper messages are drawn at this indent.
const max_indent = 12;

pub const ConvItem = struct {
    id: i32,
    title: []const u8,
    description: []const u8,
    language: []const u8,
};

pub const ConvList = struct {
    q: []const u8,
    items: []const ConvItem,
    /// Offset of the next page; meaningful when `more`.
    next: u32,
    more: bool,
    empty: bool,
};

pub const TrView = struct { id: i32, language: []const u8, content: []const u8 };

/// One message of the flattened tree (depth-first) or of a route.
pub const Row = struct {
    id: i32,
    depth: usize,
    role: []const u8,
    content: []const u8,
    translations: []const TrView,
};

pub const TreePage = struct {
    conv: ConvItem,
    rows: []const Row,
    empty: bool,
};

pub const MsgView = struct { id: i32, role: []const u8, content: []const u8 };

pub const MessageFormView = struct {
    is_edit: bool,
    id: i32,
    conversation_id: i32,
    parent_id: i32,
    /// What the message answers: the parent's text, or "New root message".
    hint: []const u8,
    role: []const u8,
    content: []const u8,
    err_role: []const u8,
    err_content: []const u8,
};

pub const TranslationFormView = struct {
    is_edit: bool,
    id: i32,
    message_id: i32,
    /// The message text being translated.
    source: []const u8,
    language: []const u8,
    content: []const u8,
    err_language: []const u8,
    err_content: []const u8,
};

pub fn convItem(c: types.Conversation) ConvItem {
    return .{ .id = c.id, .title = c.title, .description = c.description, .language = c.source_language };
}

pub fn convList(a: std.mem.Allocator, q: []const u8, offset: u32, found: []const types.Conversation) !ConvList {
    const more = found.len > page_size;
    const shown = found[0..@min(found.len, page_size)];
    const items = try a.alloc(ConvItem, shown.len);
    for (shown, items) |c, *i| i.* = convItem(c);
    return .{ .q = q, .items = items, .next = offset + page_size, .more = more, .empty = offset == 0 and shown.len == 0 };
}

fn trViews(a: std.mem.Allocator, ts: []const types.Translation) ![]const TrView {
    const out = try a.alloc(TrView, ts.len);
    for (ts, out) |t, *o| o.* = .{ .id = t.id, .language = t.language, .content = t.content };
    return out;
}

/// Depth-first flattening of the tree; siblings keep their creation order.
pub fn rows(a: std.mem.Allocator, roots: []const types.tree.Node) std.mem.Allocator.Error![]const Row {
    var list: std.ArrayList(Row) = .empty;
    try walk(a, &list, roots, 0);
    return list.items;
}

fn walk(a: std.mem.Allocator, list: *std.ArrayList(Row), nodes: []const types.tree.Node, depth: usize) std.mem.Allocator.Error!void {
    for (nodes) |n| {
        try list.append(a, .{ .id = n.id, .depth = @min(depth, max_indent), .role = n.role, .content = n.content, .translations = try trViews(a, n.translations) });
        try walk(a, list, n.children, depth + 1);
    }
}

/// A route (root first) with each message's translations.
pub fn routeRows(a: std.mem.Allocator, path: []const types.Message, translations: []const types.Translation) ![]const Row {
    const out = try a.alloc(Row, path.len);
    for (path, out, 0..) |m, *r, depth| {
        var own: std.ArrayList(types.Translation) = .empty;
        for (translations) |t| if (t.message_id == m.id) try own.append(a, t);
        r.* = .{ .id = m.id, .depth = @min(depth, max_indent), .role = m.role, .content = m.content, .translations = try trViews(a, own.items) };
    }
    return out;
}

pub fn msgView(m: types.Message) MsgView {
    return .{ .id = m.id, .role = m.role, .content = m.content };
}

pub fn messageForm(f: forms.MessageForm, is_edit: bool, id: i32, hint: []const u8) MessageFormView {
    return .{
        .is_edit = is_edit,
        .id = id,
        .conversation_id = f.conversation_id,
        .parent_id = f.parent_id,
        .hint = hint,
        .role = f.role,
        .content = f.content,
        .err_role = f.err_role,
        .err_content = f.err_content,
    };
}

pub fn translationForm(f: forms.TranslationForm, is_edit: bool, id: i32, message_id: i32, source: []const u8) TranslationFormView {
    return .{
        .is_edit = is_edit,
        .id = id,
        .message_id = message_id,
        .source = source,
        .language = f.language,
        .content = f.content,
        .err_language = f.err_language,
        .err_content = f.err_content,
    };
}

const std = @import("std");
const types = @import("../types/root.zig");
const validate = types.validate;
const forms = @import("forms.zig");

test "rows flatten depth-first and route rows carry translations" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const m = struct {
        fn mk(id: i32, parent: ?i32) types.Message {
            return .{ .id = id, .conversation_id = 1, .parent_message_id = parent, .role = "person", .content = "c", .created_at = 0, .updated_at = 0 };
        }
    }.mk;
    const msgs = [_]types.Message{ m(1, null), m(2, 1), m(3, 2), m(4, 1) };
    const trs = [_]types.Translation{.{ .id = 9, .message_id = 3, .language = "es", .content = "x", .created_at = 0, .updated_at = 0 }};
    const flat = try rows(a, try types.tree.build(a, &msgs, &trs));
    try std.testing.expectEqual(@as(usize, 4), flat.len);
    const want = [_]struct { i32, usize }{ .{ 1, 0 }, .{ 2, 1 }, .{ 3, 2 }, .{ 4, 1 } };
    for (want, flat) |w, r| {
        try std.testing.expectEqual(w[0], r.id);
        try std.testing.expectEqual(w[1], r.depth);
    }
    try std.testing.expectEqual(@as(usize, 1), flat[2].translations.len);

    const path = try routeRows(a, &.{ msgs[0], msgs[1], msgs[2] }, &trs);
    try std.testing.expectEqual(@as(usize, 2), path[2].depth);
    try std.testing.expectEqualStrings("es", path[2].translations[0].language);
}
