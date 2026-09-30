pub const Routes = struct {
    pub fn register(s: *httpz.Server(types.App)) !void {
        var router = try s.router(.{});

        router.get("/api/conversation/search", api_search, .{});
    }

    fn api_search(app: types.App, req: *httpz.Request, res: *httpz.Response) !void {
        const query = try req.query();
        const title = query.get("s") orelse {
            res.setStatus(.bad_request);
            return;
        };
        const pointer = try std.fmt.parseInt(u32, query.get("pointer") orelse "0", 10);
        const limit = try std.fmt.parseInt(u32, query.get("limit") orelse "10", 10);

        const messages = app.conversation_factory.search_conversations(title, pointer, limit, req.arena) catch |err| blk: {
            if (err == ConversationFactory.Error.ConversationSearchFailed) {
                std.log.err("failed to search conversations with title \"{s}\" and with error <{s}>\n", .{ title, @errorName(err) });
                break :blk &[_]types.Conversation{};
            }

            return err;
        };

        res.setStatus(.ok);
        res.json(messages, .{}) catch |err| {
            std.log.err("failed to send the response with error <{s}>\n", .{@errorName(err)});
            return err;
        };
    }
};

const std = @import("std");
const httpz = @import("httpz");
const types = @import("../types/root.zig");
const ConversationFactory = @import("../factories/conversation/root.zig").Conversation;
