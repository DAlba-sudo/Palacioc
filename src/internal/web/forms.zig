//! Pure parse/validate of the HTMX forms (no DB, no HTTP). Fields echo the
//! trimmed input; `err_*` hold messages ("" = valid). Rules come from
//! `types.validate`, shared with the JSON API.
pub const StringKeyValue = httpz.key_value.StringKeyValue;

pub const ConversationForm = struct {
    title: []const u8 = "",
    description: []const u8 = "",
    language: []const u8 = "",
    first_message: []const u8 = "",
    err_title: []const u8 = "",
    err_description: []const u8 = "",
    err_language: []const u8 = "",
    err_first_message: []const u8 = "",
};

pub const MessageForm = struct {
    /// Hidden fields of the "new message" form; 0 = absent.
    conversation_id: i32 = 0,
    parent_id: i32 = 0,
    role: []const u8 = "",
    content: []const u8 = "",
    err_role: []const u8 = "",
    err_content: []const u8 = "",
};

pub const TranslationForm = struct {
    /// Hidden field of the "new translation" form; 0 = absent.
    message_id: i32 = 0,
    language: []const u8 = "",
    content: []const u8 = "",
    err_language: []const u8 = "",
    err_content: []const u8 = "",
};

/// True when no `err_*` field is set.
pub fn ok(form: anytype) bool {
    inline for (std.meta.fields(@TypeOf(form))) |f| {
        if (comptime std.mem.startsWith(u8, f.name, "err_")) {
            if (@field(form, f.name).len != 0) return false;
        }
    }
    return true;
}

fn trimmed(map: *const StringKeyValue, key: []const u8) ?[]const u8 {
    const raw = map.get(key) orelse return null;
    return std.mem.trim(u8, raw, " \t\r\n");
}

fn id(map: *const StringKeyValue, key: []const u8) i32 {
    return contract.parseId(trimmed(map, key) orelse "") orelse 0;
}

/// Runs `rule`; on failure keeps the raw text for echo and records the message.
fn check(comptime rule: anytype, raw: ?[]const u8, value: *[]const u8, err: *[]const u8) void {
    if (rule(raw)) |v| {
        value.* = v;
    } else |e| {
        value.* = raw orelse "";
        err.* = validate.message(e);
    }
}

pub fn conversation(map: *const StringKeyValue) ConversationForm {
    var f: ConversationForm = .{};
    check(validate.title, trimmed(map, "title"), &f.title, &f.err_title);
    check(validate.description, trimmed(map, "description"), &f.description, &f.err_description);
    check(validate.languageOrDefault, trimmed(map, "source_language"), &f.language, &f.err_language);
    if (trimmed(map, "initial_message")) |m| {
        if (m.len > 0) check(validate.content, m, &f.first_message, &f.err_first_message);
    }
    return f;
}

pub fn message(map: *const StringKeyValue) MessageForm {
    var f: MessageForm = .{ .conversation_id = id(map, "conversation_id"), .parent_id = id(map, "parent_message_id") };
    check(validate.role, trimmed(map, "role"), &f.role, &f.err_role);
    check(validate.content, trimmed(map, "content"), &f.content, &f.err_content);
    return f;
}

pub fn translation(map: *const StringKeyValue) TranslationForm {
    var f: TranslationForm = .{ .message_id = id(map, "message_id") };
    check(validate.language, trimmed(map, "language"), &f.language, &f.err_language);
    check(validate.content, trimmed(map, "content"), &f.content, &f.err_content);
    return f;
}

const std = @import("std");
const httpz = @import("httpz");
const contract = @import("contract");
const validate = @import("../types/root.zig").validate;

fn testMap(arena: std.mem.Allocator, pairs: []const [2][]const u8) !StringKeyValue {
    var m = try StringKeyValue.init(arena, 8);
    for (pairs) |p| m.add(p[0], p[1]);
    return m;
}

test "conversation form validates, trims and defaults" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const good = try testMap(arena.allocator(), &.{ .{ "title", "  Cafe  " }, .{ "initial_message", "Hola" } });
    const f = conversation(&good);
    try std.testing.expect(ok(f));
    try std.testing.expectEqualStrings("Cafe", f.title);
    try std.testing.expectEqualStrings("en", f.language);
    try std.testing.expectEqualStrings("Hola", f.first_message);

    const bad = try testMap(arena.allocator(), &.{ .{ "title", " " }, .{ "source_language", "e_1" } });
    const b = conversation(&bad);
    try std.testing.expect(!ok(b));
    try std.testing.expectEqualStrings("Title is required.", b.err_title);
    try std.testing.expectEqualStrings("e_1", b.language);
    try std.testing.expect(b.err_language.len > 0);
}

test "message and translation forms" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const m = try testMap(arena.allocator(), &.{ .{ "parent_message_id", "7" }, .{ "content", "Hi" } });
    const mf = message(&m);
    try std.testing.expect(ok(mf));
    try std.testing.expectEqual(@as(i32, 7), mf.parent_id);
    try std.testing.expectEqualStrings("person", mf.role);

    const t = try testMap(arena.allocator(), &.{ .{ "message_id", "x" }, .{ "language", "es" } });
    const tf = translation(&t);
    try std.testing.expect(!ok(tf));
    try std.testing.expectEqual(@as(i32, 0), tf.message_id);
    try std.testing.expectEqualStrings("Content is required.", tf.err_content);
}
