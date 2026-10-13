//! Thin pg.zig helpers: parameterized queries mapped onto structs by column
//! name. Driver errors are logged and collapsed into `error.Database`.
pub const Error = error{ Database, NotFound };

/// First row mapped to `T` (strings copied into `a`), or null.
pub fn one(comptime T: type, p: *pg.Pool, a: std.mem.Allocator, sql: []const u8, args: anytype) Error!?T {
    var row = p.rowOpts(sql, args, .{ .column_names = true }) catch |err| return fail(err);
    const r = row orelse return null;
    defer row.?.deinit() catch {};
    return r.to(T, .{ .dupe = true, .allocator = a }) catch |err| fail(err);
}

pub fn all(comptime T: type, p: *pg.Pool, a: std.mem.Allocator, sql: []const u8, args: anytype) Error![]T {
    const rows = p.queryOpts(sql, args, .{ .column_names = true }) catch |err| return fail(err);
    defer rows.deinit();
    var list: std.ArrayList(T) = .empty;
    var mapper = rows.mapper(T, .{ .dupe = true, .allocator = a });
    while (mapper.next() catch |err| return fail(err)) |item| {
        list.append(a, item) catch |err| return fail(err);
    }
    return list.toOwnedSlice(a) catch |err| fail(err);
}

/// Rows affected.
pub fn exec(p: *pg.Pool, sql: []const u8, args: anytype) Error!i64 {
    return (p.exec(sql, args) catch |err| return fail(err)) orelse 0;
}

fn fail(err: anyerror) Error {
    std.log.err("database error: {s}", .{@errorName(err)});
    return error.Database;
}

const std = @import("std");
const pg = @import("pg");
