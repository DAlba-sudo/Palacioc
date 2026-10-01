pub const Conversation = struct {
    // Globals
    pub const Error = error{
        TransactionBeginFailed,
        ConversationCreationFailed,
        ConversationSearchFailed,
        MessageCreationFailed,
    };

    // Locals
    pool: ?*pg.Pool = null,

    // This takes an injected pg.Pool and returns a new
    // Conversation factory instance.
    pub fn init(self: *@This(), pool: *pg.Pool) void {
        self.pool = pool;
    }

    // Read Operations
    pub fn search_conversations(self: *const @This(), title: []const u8, pointer: u64, limit: u64, allocator: std.mem.Allocator) !std.ArrayList(types.Conversation).Slice {
        if (self.pool == null) {
            std.log.err("failed to search conversations with title \"{s}\" because the database connection pool is not initialized", .{title});
            return Error.ConversationSearchFailed;
        }
        const pool = self.pool.?;

        const search_query =
            \\ SELECT title, description, next_available_color, created_at, updated_at, id FROM conversation
            \\ WHERE title ILIKE '%' || $1 ::text || '%'
            \\ ORDER BY created_at DESC
            \\ OFFSET $2
            \\ LIMIT $3;
        ;

        var rows = pool.queryOpts(search_query, .{ title, pointer, limit }, .{ .column_names = true }) catch |err| {
            std.log.err("failed to search conversations with title \"{s}\" and with error <{s}>", .{ title, @errorName(err) });
            return Error.ConversationSearchFailed;
        };
        defer rows.deinit();

        var list: std.ArrayList(types.Conversation) = .empty;
        var mapper = rows.mapper(types.Conversation, .{ .allocator = allocator });
        while (mapper.next() catch |err| {
            std.log.err("failed to map the conversation row with title \"{s}\" and with error <{s}>", .{ title, @errorName(err) });
            rows.drain() catch {};
            return err;
        }) |c| {
            std.log.debug("found conversation with title \"{s}\" and id {d}", .{ c.title, c.id });
            try list.append(allocator, c);
        }

        return try list.toOwnedSlice(allocator);
    }

    // Write Operations
    pub fn create(
        self: *const @This(),
        title: []const u8,
        description: ?[]const u8,
        initial_message: ?[]const u8,
        initial_message_role: ?[]const u8,
    ) !void {
        if (self.pool == null) {
            std.log.err("failed to create a conversation with title \"{s}\" because the database connection pool is not initialized", .{title});
            return Error.ConversationCreationFailed;
        }
        const pool = self.pool.?;

        // Using a connection so that we can perform a rollback.
        const conn = try pool.acquire();
        defer conn.release();

        const conversation_creation_query =
            \\ INSERT INTO conversation (title, description) 
            \\ VALUES ($1, $2) RETURNING id;
        ;

        // This does not include a parent message id since it's a new
        // conversation.
        const message_creation_query =
            \\ INSERT INTO message (
            \\      content, conversation_id, role
            \\ ) VALUES ($1, $2, $3);
        ;

        conn.begin() catch |err| {
            std.log.err("failed to begin the transaction with the database for conversation title \"{s}\" and with error <{s}>", .{ title, @errorName(err) });
            return Error.TransactionBeginFailed;
        };
        errdefer |err| {
            std.log.err("failed procedure so attempting to rollback the transaction with the database for conversation title \"{s}\" and with error <{s}>", .{ title, @errorName(err) });
            conn.rollback() catch |rollback_err| {
                std.log.err("failed to rollback the transaction with the database for conversation title \"{s}\" and with error <{s}>", .{ title, @errorName(rollback_err) });
            };
        }

        var conversation_id_row = (conn.row(conversation_creation_query, .{ title, description }) catch |err| blk: {
            std.log.err("failed to create the conversation with title \"{s}\" and with error <{s}>", .{ title, @errorName(err) });
            break :blk null;
        }) orelse {
            return error.ConversationCreationFailed;
        };

        const conversation_id = try conversation_id_row.get(i32, 0);
        conversation_id_row.deinit() catch {};

        _ = (conn.exec(message_creation_query, .{ initial_message, conversation_id, initial_message_role })) catch |err| {
            std.log.err("failed to create the initial message for conversation title \"{s}\" and with error <{s}>", .{ title, @errorName(err) });
            return error.MessageCreationFailed;
        };
        conn.commit() catch |err| {
            std.log.err("failed to commit the transaction with the database for conversation title \"{s}\" and with error <{s}>", .{ title, @errorName(err) });
            return error.TransactionBeginFailed;
        };
    }
};

// Imports
const std = @import("std");
const pg = @import("pg");
const types = @import("../../types/root.zig");
