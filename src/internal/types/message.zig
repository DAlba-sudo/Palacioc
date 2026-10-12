pub const Message = struct {
    id: i32,
    conversation_id: i32,
    parent_message_id: ?i32,
    role: []const u8,
    content: []const u8,
    created_at: i64,
    updated_at: i64,

    const cols = "id, conversation_id, parent_message_id, role, content, created_at, updated_at";

    pub fn get(p: *pg.Pool, a: std.mem.Allocator, id: i32) db.Error!?Message {
        return db.one(Message, p, a, "SELECT " ++ cols ++ " FROM message WHERE id = $1", .{id});
    }

    /// Adds a root message to `conversation_id`, or a child of `parent_id`
    /// (whose conversation is used; `conversation_id`, when also given, must
    /// match). Null when the conversation or parent does not exist.
    pub fn create(p: *pg.Pool, a: std.mem.Allocator, conversation_id: ?i32, parent_id: ?i32, role: []const u8, content: []const u8) db.Error!?Message {
        if (parent_id) |parent| {
            return db.one(Message, p, a,
                "INSERT INTO message (conversation_id, parent_message_id, role, content) " ++
                    "SELECT conversation_id, id, $2, $3 FROM message WHERE id = $1 AND ($4::int IS NULL OR conversation_id = $4) " ++
                    "RETURNING " ++ cols,
                .{ parent, role, content, conversation_id });
        }
        return db.one(Message, p, a,
            "INSERT INTO message (conversation_id, role, content) SELECT id, $2, $3 FROM conversation WHERE id = $1 " ++
                "RETURNING " ++ cols,
            .{ conversation_id, role, content });
    }

    /// Only the non-null fields change.
    pub fn update(p: *pg.Pool, a: std.mem.Allocator, id: i32, content: ?[]const u8, role: ?[]const u8) db.Error!?Message {
        return db.one(Message, p, a,
            "UPDATE message SET content = COALESCE($2, content), role = COALESCE($3, role), " ++
                "updated_at = CURRENT_TIMESTAMP WHERE id = $1 RETURNING " ++ cols,
            .{ id, content, role });
    }

    /// Deletes the message, its descendants and their translations (FK cascade).
    pub fn delete(p: *pg.Pool, id: i32) db.Error!bool {
        return try db.exec(p, "DELETE FROM message WHERE id = $1", .{id}) > 0;
    }

    /// All messages of a conversation, oldest first. A parent always has a
    /// smaller id than its children.
    pub fn listByConversation(p: *pg.Pool, a: std.mem.Allocator, conversation_id: i32) db.Error![]Message {
        return db.all(Message, p, a, "SELECT " ++ cols ++ " FROM message WHERE conversation_id = $1 ORDER BY id", .{conversation_id});
    }

    /// The route: the root-to-`id` path, root first. Empty when `id` is unknown.
    pub fn route(p: *pg.Pool, a: std.mem.Allocator, id: i32) db.Error![]Message {
        return db.all(Message, p, a,
            \\ WITH RECURSIVE r AS (
            \\   SELECT m.id, m.conversation_id, m.parent_message_id, m.role, m.content, m.created_at, m.updated_at, 1 AS depth
            \\   FROM message m WHERE m.id = $1
            \\   UNION ALL
            \\   SELECT p.id, p.conversation_id, p.parent_message_id, p.role, p.content, p.created_at, p.updated_at, r.depth + 1
            \\   FROM message p JOIN r ON p.id = r.parent_message_id
            \\ )
            \\ SELECT id, conversation_id, parent_message_id, role, content, created_at, updated_at FROM r ORDER BY depth DESC
        , .{id});
    }
};

const std = @import("std");
const pg = @import("pg");
const db = @import("db.zig");
