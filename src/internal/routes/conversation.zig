pub const Routes = struct {
    pub fn register(s: *httpz.Server(types.App)) !void {
        var router = try s.router(.{});

        router.get("/api/conversation/search", api_search, .{});
        router.post("/api/conversation", api_create_with_message, .{});
    }

    const _api_search = [_]contract.Contract{
        .{ .key = "s", .location = .Query },
        .{ .key = "p", .location = .Query, .default_value = "0" },
        .{ .key = "l", .location = .Query, .default_value = "10" },
    };
    fn api_search(app: types.App, req: *httpz.Request, res: *httpz.Response) !void {
        for (_api_search) |c| {
            _ = try c.get(req);
        }

        const title = try _api_search[0].get(req);
        const pointer = std.fmt.parseInt(u64, try _api_search[1].get(req), 10) catch blk: {
            std.log.warn("failed to parse pointer parameter, using default value 0", .{});
            break :blk 0;
        };
        const limit = std.fmt.parseInt(u64, try _api_search[2].get(req), 10) catch blk: {
            std.log.warn("failed to parse limit parameter, using default value 10", .{});
            break :blk 10;
        };

        const messages = app.conversation_factory.search_conversations(title, pointer, limit, req.arena) catch |err| blk: {
            if (err == ConversationFactory.Error.ConversationSearchFailed) {
                std.log.err("failed to search conversations with title \"{s}\" and with error <{s}>", .{ title, @errorName(err) });
                break :blk &[_]types.Conversation{};
            }

            return err;
        };

        res.setStatus(.ok);
        res.json(messages, .{}) catch |err| {
            std.log.err("failed to send the response with error <{s}>", .{@errorName(err)});
            return err;
        };
    }

    const _api_create_with_message = [_]contract.Contract{
        .{
            .key = "title",
            .location = .Body,
        },
        .{ .key = "description", .location = .Body, .default_value = "" },
        .{ .key = "initial_message", .location = .Body },
        .{ .key = "initial_message_role", .location = .Body },
    };
    fn api_create_with_message(app: types.App, req: *httpz.Request, res: *httpz.Response) !void {
        for (_api_create_with_message) |c| {
            _ = try c.get(req);
        }

        const title = try _api_create_with_message[0].get(req);
        const description = try _api_create_with_message[1].get(req);
        const initial_message = try _api_create_with_message[2].get(req);
        const initial_message_role = try _api_create_with_message[3].get(req);

        app.conversation_factory.create(title, description, initial_message, initial_message_role) catch |err| blk: {
            if (err == ConversationFactory.Error.ConversationCreationFailed) {
                std.log.err("failed to create a conversation with title \"{s}\" and with error <{s}>", .{ title, @errorName(err) });
                res.setStatus(.internal_server_error);
                break :blk;
            }

            return err;
        };

        res.setStatus(.created);
    }
};

const std = @import("std");
const httpz = @import("httpz");
const types = @import("../types/root.zig");
const ConversationFactory = @import("../factories/conversation/root.zig").Conversation;
const contract = @import("contract");
