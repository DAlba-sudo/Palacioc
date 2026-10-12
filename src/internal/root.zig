pub const VERSION = "0.0.1";

pub const config = @import("config/configuration.zig");
pub const routes = @import("routes/root.zig");
pub const types = @import("types/root.zig");
pub const web = @import("web/root.zig");

test {
    _ = routes.errors;
    _ = routes.api;
    _ = types;
    _ = web;
}
