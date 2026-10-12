pub fn main(init: process.Init) !void {
    // -- Parse the configuration from the environment variables
    const settings = internal.config.Settings.from_environ(init.environ_map) catch {
        std.log.err("Failed to create a server settings object", .{});
        std.process.exit(1);
    };

    // -- Create the HTTP server configuration
    var _server_config: httpz.Config = .{
        .request = .{
            .max_form_count = 32,
        },
    };
    if (settings.palacioc_listen_all_interfaces) {
        _server_config.address = .all(settings.palacioc_listen_port);
    } else {
        _server_config.address = .localhost(settings.palacioc_listen_port);
    }

    // -- Create the "App" state shared with every handler
    var app = internal.routes.App{ .p = null, .io = init.io };
    defer if (app.p) |p| p.deinit();

    if (settings.db_connection_uri.len > 0) {
        app.p = pg.Pool.initUri(init.io, init.gpa, try .parse(settings.db_connection_uri), .{
            .size = settings.db_connection_pool_size,
        }) catch |err| blk: {
            std.log.err("Failed to create a database connection pool with error <{s}>", .{@errorName(err)});

            if (settings.db_fail_on_connection) {
                std.process.exit(1);
            }

            break :blk null;
        };
    }

    // -- Create the HTTP server
    var server = try internal.routes.Server.init(init.io, init.gpa, _server_config, app);
    defer {
        server.stop();
        server.deinit();
    }

    try internal.routes.router.register(&server);

    std.log.info("Server is listening on port {d}", .{settings.palacioc_listen_port});
    try server.listen();
}

// Generic Imports
const std = @import("std");
const process = std.process;

// Other Imports
const internal = @import("internal");
const httpz = @import("httpz");
const pg = @import("pg");
