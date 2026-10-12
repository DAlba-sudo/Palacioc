//! One integration check per endpoint group against a real Postgres. Skipped
//! unless PALACIOC_TEST_DB_URI is set, e.g.
//!   PALACIOC_TEST_DB_URI=postgres://palacioc:<password>@127.0.0.1:5432/palacioc zig build test
const Out = struct { status: u16, json: std.json.Value };

fn pool() !*pg.Pool {
    const uri = std.testing.environ.getPosix("PALACIOC_TEST_DB_URI") orelse return error.SkipZigTest;
    return pg.Pool.initUri(std.testing.io, std.testing.allocator, try .parse(uri), .{ .size = 2 });
}

/// Runs `handler` as the router would (errors become responses) and parses the JSON body.
fn call(a: std.mem.Allocator, app: App, handler: anytype, id: ?i32, form: []const u8) !Out {
    var ht = httpz.testing.init(.{ .request = .{ .max_form_count = 8 } });
    defer ht.deinit();
    ht.url("/api/test");
    if (id) |i| ht.param("id", try std.fmt.allocPrint(ht.arena, "{d}", .{i}));
    if (form.len > 0) {
        ht.header("content-type", "application/x-www-form-urlencoded");
        ht.body(form);
    }
    handler(app, ht.req, ht.res) catch |err| errors.respond(ht.req, ht.res, err);
    const pr = try ht.parseResponse();
    return .{ .status = pr.status, .json = try std.json.parseFromSliceLeaky(std.json.Value, a, pr.body, .{}) };
}

fn newId(out: Out) i32 {
    return @intCast(out.json.object.get("id").?.integer);
}

test "conversation endpoints" {
    const p = try pool();
    defer p.deinit();
    const app: App = .{ .p = p, .io = std.testing.io };
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const created = try call(a, app, api.conversation.create, null, "title=It+Conv+Zeta&source_language=pt-BR&initial_message=Ola");
    try std.testing.expectEqual(@as(u16, 201), created.status);
    const id = newId(created);
    defer _ = Conversation.delete(p, id) catch {};

    try std.testing.expectEqual(@as(u16, 400), (try call(a, app, api.conversation.create, null, "title=+")).status);

    const got = try call(a, app, api.conversation.get, id, "");
    try std.testing.expectEqualStrings("pt-BR", got.json.object.get("source_language").?.string);

    const upd = try call(a, app, api.conversation.update, id, "title=It+Conv+Zeta2");
    try std.testing.expectEqualStrings("It Conv Zeta2", upd.json.object.get("title").?.string);

    const found = try Conversation.search(p, a, "conv zeta2", 0, 10);
    try std.testing.expectEqual(@as(usize, 1), found.len);

    const tree = try call(a, app, api.conversation.tree, id, "");
    try std.testing.expectEqual(@as(usize, 1), tree.json.object.get("roots").?.array.items.len);

    try std.testing.expectEqual(@as(u16, 200), (try call(a, app, api.conversation.delete, id, "")).status);
    try std.testing.expectEqual(@as(u16, 404), (try call(a, app, api.conversation.get, id, "")).status);
}

test "message endpoints: branches, route, subtree delete" {
    const p = try pool();
    defer p.deinit();
    const app: App = .{ .p = p, .io = std.testing.io };
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const conv = try Conversation.create(p, a, "It msg", "", "en", null, "person");
    defer _ = Conversation.delete(p, conv.id) catch {};

    const root = newId(try call(a, app, api.message.create, null, try std.fmt.allocPrint(a, "conversation_id={d}&content=root", .{conv.id})));
    const child = newId(try call(a, app, api.message.create, null, try std.fmt.allocPrint(a, "parent_message_id={d}&content=child", .{root})));
    const sibling = newId(try call(a, app, api.message.create, null, try std.fmt.allocPrint(a, "parent_message_id={d}&content=sibling", .{root})));
    const leaf = newId(try call(a, app, api.message.create, null, try std.fmt.allocPrint(a, "parent_message_id={d}&content=leaf", .{child})));

    try std.testing.expectEqual(@as(u16, 400), (try call(a, app, api.message.create, null, "content=orphan")).status);
    try std.testing.expectEqual(@as(u16, 404), (try call(a, app, api.message.create, null, "parent_message_id=2000000000&content=x")).status);

    const route = try call(a, app, api.message.route, leaf, "");
    try std.testing.expectEqual(@as(usize, 3), route.json.array.items.len);
    try std.testing.expectEqual(@as(i64, root), route.json.array.items[0].object.get("message").?.object.get("id").?.integer);

    const upd = try call(a, app, api.message.update, sibling, "content=edited&role=other");
    try std.testing.expectEqualStrings("other", upd.json.object.get("role").?.string);

    try std.testing.expectEqual(@as(u16, 200), (try call(a, app, api.message.delete, child, "")).status);
    try std.testing.expectEqual(@as(u16, 404), (try call(a, app, api.message.get, leaf, "")).status);
    try std.testing.expectEqual(@as(u16, 200), (try call(a, app, api.message.get, sibling, "")).status);
}

test "translation endpoints" {
    const p = try pool();
    defer p.deinit();
    const app: App = .{ .p = p, .io = std.testing.io };
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const conv = try Conversation.create(p, a, "It tr", "", "es", "Hola", "person");
    defer _ = Conversation.delete(p, conv.id) catch {};
    const msg = (try Message.listByConversation(p, a, conv.id))[0];

    const t1 = newId(try call(a, app, api.translation.create, null, try std.fmt.allocPrint(a, "message_id={d}&language=en&content=Hello", .{msg.id})));
    _ = try call(a, app, api.translation.create, null, try std.fmt.allocPrint(a, "message_id={d}&language=en&content=Hi", .{msg.id}));
    try std.testing.expectEqual(@as(u16, 400), (try call(a, app, api.translation.create, null, try std.fmt.allocPrint(a, "message_id={d}&language=x&content=Hi", .{msg.id}))).status);
    try std.testing.expectEqual(@as(u16, 404), (try call(a, app, api.translation.create, null, "message_id=2000000000&language=en&content=Hi")).status);

    const list = try call(a, app, api.translation.listByMessage, msg.id, "");
    try std.testing.expectEqual(@as(usize, 2), list.json.array.items.len);

    const upd = try call(a, app, api.translation.update, t1, "content=Hey");
    try std.testing.expectEqualStrings("Hey", upd.json.object.get("content").?.string);

    try std.testing.expectEqual(@as(u16, 200), (try call(a, app, api.translation.delete, t1, "")).status);
    try std.testing.expectEqual(@as(u16, 404), (try call(a, app, api.translation.delete, t1, "")).status);
}

const std = @import("std");
const httpz = @import("httpz");
const pg = @import("pg");
const App = @import("../root.zig").App;
const api = @import("root.zig");
const errors = @import("../errors.zig");
const types = @import("../../types/root.zig");
const Conversation = types.Conversation;
const Message = types.Message;
