//! Resolves which root-to-leaf route of a conversation the chat pane shows.
//! Pure: works on the conversation's flat messages (id order, so parents come
//! before children and siblings are in creation order).
pub const Step = struct {
    /// Index into the `messages` given to `resolve`.
    index: usize,
    /// 1-based position among the siblings (roots count as siblings), and their number.
    pos: usize,
    count: usize,
    prev: ?i32,
    next: ?i32,
};

pub const Route = struct {
    steps: []const Step,
    /// Last message of the route; null for an empty conversation.
    leaf: ?i32,
    /// The requested selection, only when it lies on the route.
    sel: ?i32,
};

/// `leaf` pins the end of the route and wins over `sel`; `sel` makes the route
/// pass through it and continue down first children. Unknown ids are ignored.
/// With neither, the route follows the first root and first children.
pub fn resolve(a: std.mem.Allocator, messages: []const Message, sel: ?i32, leaf: ?i32) std.mem.Allocator.Error!Route {
    if (messages.len == 0) return .{ .steps = &.{}, .leaf = null, .sel = null };

    var index: std.AutoHashMapUnmanaged(i32, usize) = .empty;
    for (messages, 0..) |m, i| try index.put(a, m.id, i);

    const kids = try a.alloc(std.ArrayList(usize), messages.len);
    @memset(kids, .empty);
    var roots: std.ArrayList(usize) = .empty;
    for (messages, 0..) |m, i| {
        const parent = if (m.parent_message_id) |p| index.get(p) else null;
        if (parent) |pi| try kids[pi].append(a, i) else try roots.append(a, i);
    }

    const leaf_at = if (leaf) |l| index.get(l) else null;
    const sel_at = if (sel) |s| index.get(s) else null;

    // Chain from the root down to `bottom`, then (unless pinned) first children.
    const bottom = leaf_at orelse sel_at orelse roots.items[0];
    var chain: std.ArrayList(usize) = .empty;
    var at: ?usize = bottom;
    while (at) |i| {
        try chain.append(a, i);
        at = if (messages[i].parent_message_id) |p| index.get(p) else null;
    }
    std.mem.reverse(usize, chain.items);
    if (leaf_at == null) {
        var cur = bottom;
        while (kids[cur].items.len > 0) {
            cur = kids[cur].items[0];
            try chain.append(a, cur);
        }
    }

    const steps = try a.alloc(Step, chain.items.len);
    var sel_ok: ?i32 = null;
    for (chain.items, steps) |i, *s| {
        const sibs = if (messages[i].parent_message_id) |p| kids[index.get(p).?].items else roots.items;
        const pos = std.mem.indexOfScalar(usize, sibs, i).?;
        s.* = .{
            .index = i,
            .pos = pos + 1,
            .count = sibs.len,
            .prev = if (pos > 0) messages[sibs[pos - 1]].id else null,
            .next = if (pos + 1 < sibs.len) messages[sibs[pos + 1]].id else null,
        };
        if (sel) |sid| {
            if (messages[i].id == sid) sel_ok = sid;
        }
    }
    return .{ .steps = steps, .leaf = messages[chain.items[chain.items.len - 1]].id, .sel = sel_ok };
}

const std = @import("std");
const Message = @import("../types/root.zig").Message;

fn ids(a: std.mem.Allocator, r: Route, ms: []const Message) ![]i32 {
    const out = try a.alloc(i32, r.steps.len);
    for (r.steps, out) |s, *o| o.* = ms[s.index].id;
    return out;
}

test "resolve: default, sel, leaf and siblings" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const m = struct {
        fn mk(id: i32, parent: ?i32) Message {
            return .{ .id = id, .conversation_id = 1, .parent_message_id = parent, .role = "p", .content = "c", .created_at = 0, .updated_at = 0 };
        }
    }.mk;
    // roots 1, 7; 1 -> 2, 3; 2 -> 4; 3 -> 5; 4 -> 6
    const ms = [_]Message{ m(1, null), m(2, 1), m(3, 1), m(4, 2), m(5, 3), m(6, 4), m(7, null) };

    const def = try resolve(a, &ms, null, null);
    try std.testing.expectEqualSlices(i32, &.{ 1, 2, 4, 6 }, try ids(a, def, &ms));
    try std.testing.expectEqual(@as(?i32, 6), def.leaf);
    try std.testing.expectEqual(@as(usize, 1), def.steps[0].pos);
    try std.testing.expectEqual(@as(usize, 2), def.steps[0].count);
    try std.testing.expectEqual(@as(?i32, 7), def.steps[0].next);
    try std.testing.expectEqual(@as(?i32, 3), def.steps[1].next);

    // sel passes through and descends first children
    const via3 = try resolve(a, &ms, 3, null);
    try std.testing.expectEqualSlices(i32, &.{ 1, 3, 5 }, try ids(a, via3, &ms));
    try std.testing.expectEqual(@as(?i32, 3), via3.sel);
    try std.testing.expectEqual(@as(?i32, 2), via3.steps[1].prev);

    // leaf pins the end; sel off the route is dropped, on the route is kept
    const pinned = try resolve(a, &ms, 5, 4);
    try std.testing.expectEqualSlices(i32, &.{ 1, 2, 4 }, try ids(a, pinned, &ms));
    try std.testing.expectEqual(@as(?i32, null), pinned.sel);
    try std.testing.expectEqual(@as(?i32, 2), (try resolve(a, &ms, 2, 4)).sel);

    // second root; unknown ids fall back to the default
    try std.testing.expectEqualSlices(i32, &.{7}, try ids(a, try resolve(a, &ms, 7, null), &ms));
    try std.testing.expectEqualSlices(i32, &.{ 1, 2, 4, 6 }, try ids(a, try resolve(a, &ms, 99, 98), &ms));
    try std.testing.expectEqual(@as(?i32, null), (try resolve(a, &.{}, 1, 1)).leaf);
}
