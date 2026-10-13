//! Renders the shell template from the view builder, so a template that no
//! longer matches its view model fails here rather than at request time.
const std = @import("std");
const types = @import("../types/root.zig");
const render = @import("render.zig");
const view = @import("view.zig");

fn contains(hay: []const u8, needle: []const u8) !void {
    if (std.mem.indexOf(u8, hay, needle) == null) {
        std.debug.print("missing {s} in:\n{s}\n", .{ needle, hay });
        return error.TestExpectedContains;
    }
}

fn absent(hay: []const u8, needle: []const u8) !void {
    if (std.mem.indexOf(u8, hay, needle) != null) {
        std.debug.print("unexpected {s} in:\n{s}\n", .{ needle, hay });
        return error.TestUnexpectedContains;
    }
}

fn msg(id: i32, parent: ?i32, role: []const u8, content: []const u8) types.Message {
    return .{ .id = id, .conversation_id = 1, .parent_message_id = parent, .role = role, .content = content, .created_at = 0, .updated_at = 0 };
}

test "shell renders conversations mode, translation mode and edit modes" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;

    const conv: types.Conversation = .{ .id = 1, .title = "<Cafe>", .description = "desc & more", .source_language = "es", .created_at = 0, .updated_at = 0 };
    const ms = [_]types.Message{ msg(1, null, "waiter", "Hola <b>"), msg(2, 1, "guest", "Un cafe"), msg(3, 1, "guest", "Agua") };
    const trs = [_]types.Translation{.{ .id = 7, .message_id = 1, .language = "en", .content = "Hello", .created_at = 0, .updated_at = 0 }};

    // Conversations mode: cards (escaped, selected), branch switcher, datalist, composer.
    const cards = try render.renderAlloc(io, a, "shell", true, try view.shell(a, .{ .state = .{ .conv = 1 }, .conv = conv, .messages = &ms, .translations = &trs, .cards = &.{conv} }));
    try contains(cards, "<!doctype html>");
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, cards, "id=\"shell\""));
    try contains(cards, "&lt;Cafe&gt;");
    try contains(cards, "class=\"card sel\"");
    try contains(cards, "<h1>Conversations</h1>");
    try contains(cards, "Hola &lt;b&gt;");
    try contains(cards, "title=\"1 translation\"");
    try contains(cards, "Branch 1 of 2"); // the guest replies fork under message 1
    try contains(cards, "2. guest: Agua"); // the other branch is previewed
    try contains(cards, "/ui/conversation/1?via=3");
    try contains(cards, "Delete this message and its 2 replies?");
    try contains(cards, "data-pane=\"chat\"");
    try absent(cards, "Branch from here"); // only on the selected bubble
    try contains(cards, "<option value=\"guest\">");
    try contains(cards, "<option value=\"person\">");
    try contains(cards, "id=\"compose-text\"");
    try absent(cards, "Alternative Translations");

    // Translation mode for message 1, bare (htmx) response without layout.
    const tr = try render.renderAlloc(io, a, "shell", false, try view.shell(a, .{ .state = .{ .conv = 1, .sel = 1, .leaf = 2 }, .conv = conv, .messages = &ms, .translations = &trs }));
    try absent(tr, "<!doctype html>");
    try contains(tr, "class=\"bubble sel\"");
    try contains(tr, "Alternative Translations");
    try contains(tr, "Enter a new translation here...");
    try contains(tr, "hx-post=\"/ui/message/1/translations?sel=1&amp;leaf=2\"");
    try contains(tr, "name=\"sel\" value=\"1\"");
    try contains(tr, "Branching from: Hola &lt;b&gt;");
    try contains(tr, "Branch from here");
    try contains(tr, "<datalist id=\"langs\">");
    try contains(tr, "<span class=\"lang\">en</span>");
    try absent(tr, "<h1>Conversations</h1>");

    // Edit translation prefills and PUTs; edit message shows its form.
    const et = try render.renderAlloc(io, a, "shell", false, try view.shell(a, .{ .state = .{ .conv = 1, .sel = 1, .edit = .{ .translation = 7 } }, .conv = conv, .messages = &ms, .translations = &trs }));
    try contains(et, "hx-put=\"/ui/translation/7?sel=1&amp;leaf=2\"");
    try contains(et, ">Hello</textarea>");
    const em = try render.renderAlloc(io, a, "shell", false, try view.shell(a, .{ .state = .{ .conv = 1, .sel = 2, .edit = .message }, .conv = conv, .messages = &ms }));
    try contains(em, "Edit message");

    // Home: no conversation, composer disabled.
    const home = try render.renderAlloc(io, a, "shell", false, try view.shell(a, .{ .state = .{} }));
    try contains(home, "Open a conversation to start.");
    try contains(home, "disabled");
}

test "shell in a translated language renders the toggle, marked fallback and lang attributes" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const conv: types.Conversation = .{ .id = 1, .title = "T", .description = "", .source_language = "en", .created_at = 0, .updated_at = 0 };
    const ms = [_]types.Message{ msg(1, null, "a", "Hello"), msg(2, 1, "b", "Bye"), msg(3, 1, "b", "Other") };
    const trs = [_]types.Translation{
        .{ .id = 1, .message_id = 1, .language = "es", .content = "Hola <b>", .created_at = 0, .updated_at = 1 },
        .{ .id = 2, .message_id = 1, .language = "es", .content = "Buenas", .created_at = 0, .updated_at = 2 },
        .{ .id = 3, .message_id = 2, .language = "fr", .content = "Salut", .created_at = 0, .updated_at = 1 },
    };
    const out = try render.renderAlloc(std.testing.io, a, "shell", false, try view.shell(a, .{ .state = .{ .lang = "es", .sel = 1 }, .conv = conv, .messages = &ms, .translations = &trs }));
    try contains(out, "<legend>Show messages in</legend>");
    try contains(out, "value=\"es\" checked");
    try contains(out, "Source (en)");
    try contains(out, "<span lang=\"es\">Buenas</span>"); // newest of two es translations
    try contains(out, "<span class=\"more\">+1</span>");
    try contains(out, "id=\"chat-log\" class=\"chat-log\" lang=\"es\"");
    try contains(out, "name=\"lang\" value=\"es\""); // composer keeps the language
    try contains(out, "/ui/conversation/1?sel=1&amp;leaf=2&amp;lang=es");
    try absent(out, "Hola <b>");

    const source = try render.renderAlloc(std.testing.io, a, "shell", false, try view.shell(a, .{ .state = .{ .lang = "fr" }, .conv = conv, .messages = &ms, .translations = &trs }));
    try contains(source, "<span lang=\"fr\">Salut</span>"); // route 1 -> 2; only message 2 has a fr translation
    try contains(source, "<span lang=\"en\">Hello</span>");
    try contains(source, "class=\"bubble untranslated\""); // message 1 lacks fr
    try contains(source, "<span class=\"src-tag\">source</span>");
    try contains(source, "title=\"No fr translation yet\"");
}
