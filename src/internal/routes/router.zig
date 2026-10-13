//! Route table: JSON under /api, HTMX under /ui (and the `/` page).
pub fn register(server: *Server) !void {
    var r = try server.router(.{});

    r.get("/health", routes.health, .{});

    r.get("/api/conversation/search", api.conversation.search, .{});
    r.post("/api/conversation", api.conversation.create, .{});
    r.get("/api/conversation/:id", api.conversation.get, .{});
    r.put("/api/conversation/:id", api.conversation.update, .{});
    r.delete("/api/conversation/:id", api.conversation.delete, .{});
    r.get("/api/conversation/:id/tree", api.conversation.tree, .{});

    r.post("/api/message", api.message.create, .{});
    r.get("/api/message/:id", api.message.get, .{});
    r.put("/api/message/:id", api.message.update, .{});
    r.delete("/api/message/:id", api.message.delete, .{});
    r.get("/api/message/:id/route", api.message.route, .{});
    r.get("/api/message/:id/translations", api.translation.listByMessage, .{});

    r.post("/api/translation", api.translation.create, .{});
    r.put("/api/translation/:id", api.translation.update, .{});
    r.delete("/api/translation/:id", api.translation.delete, .{});

    r.get("/", web.handlers.home, .{});
    r.get("/ui/conversation/:id", web.handlers.conversationPage, .{});
    r.post("/ui/conversations", web.handlers.createConversation, .{});
    r.delete("/ui/conversation/:id", web.handlers.deleteConversation, .{});
    r.post("/ui/conversation/:id/messages", web.handlers.messageCreate, .{});
    r.put("/ui/message/:id", web.handlers.messageUpdate, .{});
    r.delete("/ui/message/:id", web.handlers.messageDelete, .{});
    r.post("/ui/message/:id/translations", web.handlers.translationCreate, .{});
    r.put("/ui/translation/:id", web.handlers.translationUpdate, .{});
    r.delete("/ui/translation/:id", web.handlers.translationDelete, .{});
    r.get(web.static.htmx_path, web.static.htmxJs, .{});
    r.get(web.static.css_path, web.static.appCss, .{});
}

const routes = @import("root.zig");
const Server = routes.Server;
const api = routes.api;
const web = @import("../web/root.zig");
