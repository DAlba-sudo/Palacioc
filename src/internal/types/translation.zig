pub const Translation = struct {
    id: i32,
    message_id: i32,
    language: []const u8,
    content: []const u8,
    created_at: i64,
    updated_at: i64,

    const cols = "id, message_id, language, content, created_at, updated_at";

    pub fn get(p: *pg.Pool, a: std.mem.Allocator, id: i32) db.Error!?Translation {
        return db.one(Translation, p, a, "SELECT " ++ cols ++ " FROM translation WHERE id = $1", .{id});
    }

    /// Null when the message does not exist.
    pub fn create(p: *pg.Pool, a: std.mem.Allocator, message_id: i32, language: []const u8, content: []const u8) db.Error!?Translation {
        return db.one(Translation, p, a,
            "INSERT INTO translation (message_id, language, content) SELECT id, $2, $3 FROM message WHERE id = $1 RETURNING " ++ cols,
            .{ message_id, language, content });
    }

    pub fn listByMessage(p: *pg.Pool, a: std.mem.Allocator, message_id: i32) db.Error![]Translation {
        return db.all(Translation, p, a, "SELECT " ++ cols ++ " FROM translation WHERE message_id = $1 ORDER BY id", .{message_id});
    }

    /// Translations of every message in a conversation, oldest first.
    pub fn listByConversation(p: *pg.Pool, a: std.mem.Allocator, conversation_id: i32) db.Error![]Translation {
        return db.all(Translation, p, a,
            "SELECT t.id, t.message_id, t.language, t.content, t.created_at, t.updated_at FROM translation t " ++
                "JOIN message m ON m.id = t.message_id WHERE m.conversation_id = $1 ORDER BY t.id",
            .{conversation_id});
    }

    /// Only the non-null fields change.
    pub fn update(p: *pg.Pool, a: std.mem.Allocator, id: i32, language: ?[]const u8, content: ?[]const u8) db.Error!?Translation {
        return db.one(Translation, p, a,
            "UPDATE translation SET language = COALESCE($2, language), content = COALESCE($3, content), " ++
                "updated_at = CURRENT_TIMESTAMP WHERE id = $1 RETURNING " ++ cols,
            .{ id, language, content });
    }

    pub fn delete(p: *pg.Pool, id: i32) db.Error!bool {
        return try db.exec(p, "DELETE FROM translation WHERE id = $1", .{id}) > 0;
    }
};

const std = @import("std");
const pg = @import("pg");
const db = @import("db.zig");
