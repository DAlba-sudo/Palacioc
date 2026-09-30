pub const Settings = struct {
    db_connection_uri: []const u8 = "postgres://postgres:postgres@localhost:5432/postgres",
    db_connection_pool_size: u16 = 10,
    db_fail_on_connection: bool = true,

    palacioc_listen_port: u16 = 8080,
    palacioc_listen_all_interfaces: bool = true,

    pub fn from_environ(environ_map: *process.Environ.Map) !Settings {
        var settings = Settings{};
        const db_connection_uri = environ_map.get("PALACIOC_DB_CONNECTION_URI");
        if (db_connection_uri) |uri| {
            std.log.debug("postgres connection uri caught @config time '{s}'", .{uri});
            settings.db_connection_uri = uri;
        }

        const db_connection_pool_size = environ_map.get("PALACIOC_DB_CONNECTION_POOL_SIZE");
        if (db_connection_pool_size) |size_str| {
            const size = std.fmt.parseInt(u16, size_str, 10) catch |err| {
                std.log.err("Failed to parse DB_CONNECTION_POOL_SIZE: {}\n", .{err});
                return error.InvalidEnvironmentVariable;
            };
            settings.db_connection_pool_size = size;
        }

        if (environ_map.get("PALACIOC_DB_FAIL_ON_CONNECTION")) |fail_str| {
            settings.db_fail_on_connection = std.mem.eql(u8, "true", fail_str);
        }

        const palacioc_listen_port = environ_map.get("PALACIOC_LISTEN_PORT");
        if (palacioc_listen_port) |port_str| {
            const port = std.fmt.parseInt(u16, port_str, 10) catch |err| {
                std.log.err("Failed to parse PALACIOC_LISTEN_PORT: {}\n", .{err});
                return error.InvalidEnvironmentVariable;
            };
            settings.palacioc_listen_port = port;
        }

        const palacioc_listen_all_interfaces = environ_map.get("PALACIOC_LISTEN_ALL_INTERFACES");
        if (palacioc_listen_all_interfaces) |listen_all_str| {
            settings.palacioc_listen_all_interfaces = std.mem.eql(u8, "true", listen_all_str);
        }

        return settings;
    }
};

const std = @import("std");
const process = std.process;
