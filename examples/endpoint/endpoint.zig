const std = @import("std");
const zap = @import("zap");
const Users = @import("users.zig");
const User = Users.User;

// the Endpoint

pub const Self = @This();

var alloc: std.mem.Allocator = undefined;
var endpoint: zap.SimpleEndpoint = undefined;
var users: Users = undefined;

// 100MB of json buffer
var jsonbuf: [100 * 1024 * 1024]u8 = undefined;

pub fn init(
    a: std.mem.Allocator,
    user_path: []const u8,
) void {
    users = Users.init(a);
    alloc = a;
    endpoint = zap.SimpleEndpoint.init(.{
        .path = user_path,
        .get = getUser,
        .post = postUser,
        .put = putUser,
        .delete = deleteUser,
    });
}

pub fn getUsers() *Users {
    return &users;
}

pub fn getUserEndpoint() *zap.SimpleEndpoint {
    return &endpoint;
}

fn userIdFromPath(path: []const u8) ?usize {
    if (path.len >= endpoint.settings.path.len + 2) {
        if (path[endpoint.settings.path.len] != '/') {
            return null;
        }
        const idstr = path[endpoint.settings.path.len + 1 ..];
        return std.fmt.parseUnsigned(usize, idstr, 10) catch null;
    }
    return null;
}

fn getUser(e: *zap.SimpleEndpoint, r: zap.SimpleRequest) void {
    if (r.path) |path| {
        // /users
        if (path.len == e.settings.path.len) {
            return listUsers(e, r);
        }
        if (userIdFromPath(path)) |id| {
            if (users.get(id)) |user| {
                if (zap.stringifyBuf(&jsonbuf, user, .{})) |json| {
                    _ = r.sendJson(json);
                }
            }
        }
    }
}

fn listUsers(e: *zap.SimpleEndpoint, r: zap.SimpleRequest) void {
    _ = e;
    var l: std.ArrayList(User) = std.ArrayList(User).init(alloc);
    if (users.list(&l)) {} else |_| {
        return;
    }
    if (zap.stringifyArrayListBuf(&jsonbuf, User, &l, .{})) |maybe_json| {
        if (maybe_json) |json| {
            _ = r.sendJson(json);
        }
    } else |_| {
        return;
    }
}

fn postUser(e: *zap.SimpleEndpoint, r: zap.SimpleRequest) void {
    _ = e;
    if (r.body) |body| {
        var stream = std.json.TokenStream.init(body);
        var maybe_user: ?User = std.json.parse(
            User,
            &stream,
            .{ .allocator = alloc },
        ) catch null;
        if (maybe_user) |u| {
            defer std.json.parseFree(User, u, .{ .allocator = alloc });
            if (users.addByName(u.first_name, u.last_name)) |id| {
                if (zap.stringifyBuf(&jsonbuf, .{ .status = "OK", .id = id }, .{})) |json| {
                    _ = r.sendJson(json);
                }
            } else |_| {
                return;
            }
        }
    }
}

fn putUser(e: *zap.SimpleEndpoint, r: zap.SimpleRequest) void {
    _ = e;
    if (r.path) |path| {
        if (userIdFromPath(path)) |id| {
            if (users.get(id)) |_| {
                if (r.body) |body| {
                    var stream = std.json.TokenStream.init(body);
                    var maybe_user: ?User = std.json.parse(
                        User,
                        &stream,
                        .{ .allocator = alloc },
                    ) catch null;
                    if (maybe_user) |u| {
                        defer std.json.parseFree(
                            User,
                            u,
                            .{ .allocator = alloc },
                        );
                        if (users.update(id, u.first_name, u.last_name)) {
                            if (zap.stringifyBuf(&jsonbuf, .{
                                .status = "OK",
                                .id = id,
                            }, .{})) |json| {
                                _ = r.sendJson(json);
                            }
                        } else {
                            if (zap.stringifyBuf(&jsonbuf, .{
                                .status = "ERROR",
                                .id = id,
                            }, .{})) |json| {
                                _ = r.sendJson(json);
                            }
                        }
                    }
                }
            }
        }
    }
}

fn deleteUser(e: *zap.SimpleEndpoint, r: zap.SimpleRequest) void {
    _ = e;
    if (r.path) |path| {
        if (userIdFromPath(path)) |id| {
            if (users.delete(id)) {
                if (zap.stringifyBuf(&jsonbuf, .{ .status = "OK", .id = id }, .{})) |json| {
                    _ = r.sendJson(json);
                }
            } else {
                if (zap.stringifyBuf(&jsonbuf, .{
                    .status = "ERROR",
                    .id = id,
                }, .{})) |json| {
                    _ = r.sendJson(json);
                }
            }
        }
    }
}