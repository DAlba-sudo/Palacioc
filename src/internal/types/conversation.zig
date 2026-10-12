pub const Conversation = struct {
    id: i32,
    title: []const u8,
    description: []const u8,
    source_language: []const u8,
    created_at: i64,
    updated_at: i64,

    const cols = "id, title, description, source_language, created_at, updated_at";

    /// Case-insensitive substring match on the title, newest first.
    pub fn search(p: *pg.Pool, a: std.mem.Allocator, text: []const u8, offset: u32, limit: u32) db.Error![]Conversation {
        return db.all(Conversation, p, a, "SELECT " ++ cols ++ " FROM conversation WHERE position(lower($1::text) in lower(title)) > 0 " ++
            "ORDER BY created_at DESC, id DESC OFFSET $2::int LIMIT $3::int", .{ text, offset, limit });
    }

    pub fn get(p: *pg.Pool, a: std.mem.Allocator, id: i32) db.Error!?Conversation {
        return db.one(Conversation, p, a, "SELECT " ++ cols ++ " FROM conversation WHERE id = $1", .{id});
    }

    /// Creates the conversation and, when `first_message` is set, its root
    /// message in one statement (atomic).
    pub fn create(p: *pg.Pool, a: std.mem.Allocator, title: []const u8, description: []const u8, language: []const u8, first_message: ?[]const u8, role: []const u8) db.Error!Conversation {
        const sql =
            \\ WITH c AS (
            \\   INSERT INTO conversation (title, description, source_language) VALUES ($1, $2, $3)
            \\   RETURNING id, title, description, source_language, created_at, updated_at
            \\ ), m AS (
            \\   INSERT INTO message (conversation_id, role, content)
            \\   SELECT id, $5, $4::text FROM c WHERE $4::text IS NOT NULL
            \\ )
            \\ SELECT id, title, description, source_language, created_at, updated_at FROM c
        ;
        return (try db.one(Conversation, p, a, sql, .{ title, description, language, first_message, role })) orelse error.Database;
    }

    /// Only the non-null fields change.
    pub fn update(p: *pg.Pool, a: std.mem.Allocator, id: i32, title: ?[]const u8, description: ?[]const u8, language: ?[]const u8) db.Error!?Conversation {
        return db.one(Conversation, p, a, "UPDATE conversation SET title = COALESCE($2, title), description = COALESCE($3, description), " ++
            "source_language = COALESCE($4, source_language), updated_at = CURRENT_TIMESTAMP WHERE id = $1 RETURNING " ++ cols, .{ id, title, description, language });
    }

    /// Cascades to messages and translations. False when the id is unknown.
    pub fn delete(p: *pg.Pool, id: i32) db.Error!bool {
        return try db.exec(p, "DELETE FROM conversation WHERE id = $1", .{id}) > 0;
    }
};

const std = @import("std");
const pg = @import("pg");
const db = @import("db.zig");
