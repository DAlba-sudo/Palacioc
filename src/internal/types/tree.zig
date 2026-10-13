//! A conversation as nested messages ("routes" are root-to-leaf paths).
pub const Node = struct {
    id: i32,
    parent_message_id: ?i32,
    role: []const u8,
    content: []const u8,
    created_at: i64,
    updated_at: i64,
    translations: []const Translation,
    children: []const Node,
};

/// A message with its translations, no nesting (safe to serialize at any depth).
pub const Flat = struct {
    id: i32,
    parent_message_id: ?i32,
    role: []const u8,
    content: []const u8,
    created_at: i64,
    updated_at: i64,
    translations: []const Translation,
};

/// One entry per message, in the given (id) order.
pub fn flat(a: std.mem.Allocator, messages: []const Message, translations: []const Translation) std.mem.Allocator.Error![]const Flat {
    var own: std.AutoHashMapUnmanaged(i32, std.ArrayList(Translation)) = .empty;
    for (translations) |t| {
        const slot = try own.getOrPut(a, t.message_id);
        if (!slot.found_existing) slot.value_ptr.* = .empty;
        try slot.value_ptr.append(a, t);
    }
    const out = try a.alloc(Flat, messages.len);
    for (messages, out) |m, *f| f.* = .{
        .id = m.id,
        .parent_message_id = m.parent_message_id,
        .role = m.role,
        .content = m.content,
        .created_at = m.created_at,
        .updated_at = m.updated_at,
        .translations = if (own.get(m.id)) |l| l.items else &.{},
    };
    return out;
}

/// Builds the forest from a conversation's flat rows. `messages` must be in id
/// order (a parent's id is smaller than its children's); `translations` may be
/// in any order. Everything is allocated in `a`.
pub fn build(a: std.mem.Allocator, messages: []const Message, translations: []const Translation) std.mem.Allocator.Error![]const Node {
    var index: std.AutoHashMapUnmanaged(i32, usize) = .empty;
    for (messages, 0..) |m, i| try index.put(a, m.id, i);

    var own: std.AutoHashMapUnmanaged(i32, std.ArrayList(Translation)) = .empty;
    for (translations) |t| {
        const slot = try own.getOrPut(a, t.message_id);
        if (!slot.found_existing) slot.value_ptr.* = .empty;
        try slot.value_ptr.append(a, t);
    }

    const kids = try a.alloc(std.ArrayList(Node), messages.len);
    @memset(kids, .empty);
    var roots: std.ArrayList(Node) = .empty;

    // Children come after their parent, so walking backwards finishes each
    // node's children before the node itself.
    var i = messages.len;
    while (i > 0) {
        i -= 1;
        const m = messages[i];
        std.mem.reverse(Node, kids[i].items); // appended newest-first
        const node: Node = .{
            .id = m.id,
            .parent_message_id = m.parent_message_id,
            .role = m.role,
            .content = m.content,
            .created_at = m.created_at,
            .updated_at = m.updated_at,
            .translations = if (own.get(m.id)) |l| l.items else &.{},
            .children = kids[i].items,
        };
        const parent = if (m.parent_message_id) |pid| index.get(pid) else null;
        if (parent) |pi| try kids[pi].append(a, node) else try roots.append(a, node);
    }
    std.mem.reverse(Node, roots.items);
    return roots.items;
}

const std = @import("std");
const Message = @import("message.zig").Message;
const Translation = @import("translation.zig").Translation;

test "deep chains serialize flat and build without recursion limits" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const n = 300;
    const msgs = try a.alloc(Message, n);
    for (msgs, 0..) |*m, i| m.* = .{ .id = @intCast(i + 1), .conversation_id = 1, .parent_message_id = if (i == 0) null else @intCast(i), .role = "person", .content = "c", .created_at = 0, .updated_at = 0 };
    const out = try flat(a, msgs, &.{});
    var aw: std.Io.Writer.Allocating = .init(a);
    try std.json.Stringify.value(.{ .messages = out }, .{}, &aw.writer);
    try std.testing.expect(aw.written().len > n);
    try std.testing.expectEqual(@as(usize, 1), (try build(a, msgs, &.{})).len);
}

test "build nests children and translations in creation order" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const m = struct {
        fn mk(id: i32, parent: ?i32) Message {
            return .{ .id = id, .conversation_id = 1, .parent_message_id = parent, .role = "person", .content = "c", .created_at = 0, .updated_at = 0 };
        }
    }.mk;
    const msgs = [_]Message{ m(1, null), m(2, 1), m(3, 1), m(4, 2), m(5, null) };
    const trs = [_]Translation{
        .{ .id = 1, .message_id = 3, .language = "es", .content = "a", .created_at = 0, .updated_at = 0 },
        .{ .id = 2, .message_id = 3, .language = "es", .content = "b", .created_at = 0, .updated_at = 0 },
    };
    const roots = try build(arena.allocator(), &msgs, &trs);
    try std.testing.expectEqual(@as(usize, 2), roots.len);
    try std.testing.expectEqual(@as(i32, 1), roots[0].id);
    try std.testing.expectEqual(@as(i32, 5), roots[1].id);
    try std.testing.expectEqual(@as(usize, 2), roots[0].children.len);
    try std.testing.expectEqual(@as(i32, 2), roots[0].children[0].id);
    try std.testing.expectEqual(@as(i32, 4), roots[0].children[0].children[0].id);
    try std.testing.expectEqual(@as(usize, 2), roots[0].children[1].translations.len);
    try std.testing.expectEqualStrings("b", roots[0].children[1].translations[1].content);
}
