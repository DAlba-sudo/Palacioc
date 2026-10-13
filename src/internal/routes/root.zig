pub const api = @import("api/root.zig");
pub const errors = @import("errors.zig");
pub const router = @import("router.zig");

/// Shared handler state (read-only after startup; the pool is thread-safe).
pub const App = struct {
    p: ?*pg.Pool,
    io: std.Io,

    pub fn pool(self: App) error{NoDatabase}!*pg.Pool {
        return self.p orelse error.NoDatabase;
    }

    // httpz hooks: anything a handler returns as an error lands here.
    pub fn uncaughtError(_: App, req: *httpz.Request, res: *httpz.Response, err: anyerror) void {
        errors.respond(req, res, err);
    }

    pub fn notFound(_: App, req: *httpz.Request, res: *httpz.Response) !void {
        errors.respond(req, res, error.NotFound);
    }
};
pub const Server = httpz.Server(App);

pub fn health(_: App, _: *httpz.Request, res: *httpz.Response) !void {
    try res.json(.{ .version = @import("../root.zig").VERSION }, .{});
}

const std = @import("std");
const httpz = @import("httpz");
const pg = @import("pg");
