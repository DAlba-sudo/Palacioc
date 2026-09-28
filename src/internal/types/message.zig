pub const Message = struct {
    content: []const u8,
    conversation_id: i64,
    role: []const u8,
    parent_message_id: ?i64,

    created_at: i64,
    updated_at: i64,
    id: i64,
};
