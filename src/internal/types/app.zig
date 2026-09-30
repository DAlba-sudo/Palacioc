// This is the App type, which is used to represent the application state and configuration
// passed in via httpz to the request handler.

// This should only contain thread-safe things.
pub const App = struct {
    pool: ?*pg.Pool,
    conversation_factory: ConversationFactory,
};

const pg = @import("pg");
const ConversationFactory = @import("../factories/conversation/root.zig").Conversation;
