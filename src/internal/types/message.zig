pub const Message = struct {
    content: []const u8,
    conversation_id: i32,
    role: []const u8,
    parent_message_id: ?i32,

    created_at: i64,
    updated_at: i64,
    id: i32,
};
