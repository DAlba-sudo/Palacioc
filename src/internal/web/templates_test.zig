//! Renders every page/fragment template with sample view models, so a template
//! that no longer matches its view model fails here rather than at request time.
const std = @import("std");
const forms = @import("forms.zig");
const render = @import("render.zig");
const view = @import("view.zig");

fn contains(hay: []const u8, needle: []const u8) !void {
    if (std.mem.indexOf(u8, hay, needle) == null) {
        std.debug.print("missing {s} in:\n{s}\n", .{ needle, hay });
        return error.TestExpectedContains;
    }
}

test "templates render with their view models" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;

    const items = [_]view.ConvItem{.{ .id = 4, .title = "<Cafe>", .description = "d", .language = "es" }};
    const list: view.ConvList = .{ .q = "", .items = &items, .next = 10, .more = true, .empty = false };
    const form: forms.ConversationForm = .{ .title = "", .err_title = "Title is required.", .language = "en" };
    const home = try render.renderAlloc(io, a, "home", true, .{ .list = list, .form = form });
    try contains(home, "&lt;Cafe&gt;");
    try contains(home, "Title is required.");
    try contains(home, "\"p\": 10");
    try contains(home, "<!doctype html>");
    try contains(try render.renderAlloc(io, a, "list_fragment", false, .{ .list = list }), "/ui/conversation/4");

    const trs = [_]view.TrView{.{ .id = 9, .language = "en", .content = "Hello" }};
    const rows = [_]view.Row{
        .{ .id = 1, .depth = 0, .role = "person", .content = "Hola", .translations = &trs },
        .{ .id = 2, .depth = 1, .role = "other", .content = "Que?", .translations = &.{} },
    };
    const page: view.TreePage = .{ .conv = view.convItem(.{ .id = 4, .title = "T", .description = "", .source_language = "es", .created_at = 0, .updated_at = 0 }), .rows = &rows, .empty = false };
    const conv = try render.renderAlloc(io, a, "conversation_page", false, .{ .page = page });
    try contains(conv, "id=\"panel\"");
    try contains(conv, "--depth: 1");
    try contains(conv, "/ui/translation/9/edit");
    try contains(try render.renderAlloc(io, a, "tree_fragment", false, .{ .page = page }), "hx-trigger=\"tree-changed from:body\"");

    const msg: view.MsgView = .{ .id = 1, .role = "person", .content = "Hola" };
    const menu = try render.renderAlloc(io, a, "message_menu", false, .{ .msg = msg });
    for ([_][]const u8{ "Add a translation", "Add a new message (new branch)", "Edit", "Delete" }) |label| try contains(menu, label);
    try contains(try render.renderAlloc(io, a, "route_panel", false, .{ .msg = msg, .steps = @as([]const view.Row, &rows) }), "Hello");

    const mf = view.messageForm(.{ .parent_id = 1, .content = "", .err_content = "Content is required." }, false, 0, "Hola");
    try contains(try render.renderAlloc(io, a, "message_form", false, .{ .form = mf }), "name=\"parent_message_id\" value=\"1\"");
    const mf_edit = view.messageForm(.{ .content = "x" }, true, 7, "");
    try contains(try render.renderAlloc(io, a, "message_form", false, .{ .form = mf_edit }), "hx-put=\"/ui/message/7\"");
    const tf = view.translationForm(.{ .err_language = "bad" }, false, 0, 1, "Hola");
    try contains(try render.renderAlloc(io, a, "translation_form", false, .{ .form = tf }), "bad");
}
