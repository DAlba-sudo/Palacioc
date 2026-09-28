pub const Conversation = struct {
    title: []const u8,
    description: ?[]const u8,
    next_available_color: i64,
    created_at: i64,
    updated_at: i64,
    id: i64,
};

const std = @import("std");
