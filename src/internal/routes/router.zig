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
    r.get("/ui/conversations", web.handlers.list, .{});
    r.post("/ui/conversations", web.handlers.createConversation, .{});
    r.get("/ui/conversation/:id", web.handlers.conversationPage, .{});
    r.get("/ui/conversation/:id/tree", web.handlers.tree, .{});
    r.delete("/ui/conversation/:id", web.handlers.deleteConversation, .{});

    r.get("/ui/message/new", web.handlers.messageNew, .{});
    r.post("/ui/message", web.handlers.messageCreate, .{});
    r.get("/ui/message/:id/menu", web.handlers.messageMenu, .{});
    r.get("/ui/message/:id/route", web.handlers.messageRoute, .{});
    r.get("/ui/message/:id/edit", web.handlers.messageEdit, .{});
    r.put("/ui/message/:id", web.handlers.messageUpdate, .{});
    r.delete("/ui/message/:id", web.handlers.messageDelete, .{});

    r.get("/ui/translation/new", web.handlers.translationNew, .{});
    r.post("/ui/translation", web.handlers.translationCreate, .{});
    r.get("/ui/translation/:id/edit", web.handlers.translationEdit, .{});
    r.put("/ui/translation/:id", web.handlers.translationUpdate, .{});
    r.delete("/ui/translation/:id", web.handlers.translationDelete, .{});

    r.get("/ui/panel/close", web.handlers.panelClose, .{});
    r.get(web.static.htmx_path, web.static.htmxJs, .{});
    r.get(web.static.css_path, web.static.appCss, .{});
}

const routes = @import("root.zig");
const Server = routes.Server;
const api = routes.api;
const web = @import("../web/root.zig");
