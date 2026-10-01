pub fn main(init: process.Init) !void {
    // -- Parse the configuration from the environment variables
    const settings = internal.ServerSettings.from_environ(init.environ_map) catch {
        std.log.err("Failed to create a server settings object", .{});
        std.process.exit(1);
    };

    // -- Create the HTTP server configuration
    var _server_config: httpz.Config = .{
        .request = .{
            .max_form_count = 25,
        },
    };
    if (settings.palacioc_listen_all_interfaces) {
        _server_config.address = .all(settings.palacioc_listen_port);
    } else {
        _server_config.address = .localhost(settings.palacioc_listen_port);
    }

    // -- Create the "App" type
    var app = internal.types.App{
        .pool = null,
        .conversation_factory = internal.ConversationFactory{},
    };

    if (settings.db_connection_uri.len > 0) {
        app.pool = pg.Pool.initUri(init.io, init.gpa, try .parse(settings.db_connection_uri), .{
            .size = settings.db_connection_pool_size,
        }) catch |err| blk: {
            std.log.err("Failed to create a database connection pool with error <{s}>", .{@errorName(err)});

            if (settings.db_fail_on_connection) {
                std.process.exit(1);
            }

            break :blk null;
        };

        app.conversation_factory.pool = app.pool;
    }

    // -- Create the HTTP server
    var server = try httpz.Server(internal.types.App).init(init.io, init.gpa, _server_config, app);
    defer {
        server.stop();
        server.deinit();
    }

    try internal.ConversationRoutes.register(&server);

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
