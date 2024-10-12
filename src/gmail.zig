const std = @import("std");
const auth = @import("gmail_auth.zig");
const messages = @import("gmail_messages.zig");

pub const Gmail = struct {
    const Self = @This();
    allocator: *const std.mem.Allocator,
    access_token: []const u8,
    refresh_token: []const u8,

    pub fn init(allocator: *const std.mem.Allocator) Self {
        return Self{ .allocator = allocator, .access_token = undefined, .refresh_token = undefined };
    }

    pub fn authenticate(self: *Self) !void {
        try auth.authenticate(self);
    }

    pub fn listEmails(self: *Self) !void {
        try messages.listEmails(self);
    }

    pub fn sendAuthenticatedRequest(self: *Self, path: []const u8, method: std.http.Method) !std.ArrayList(u8) {
        return auth.sendAuthenticatedRequest(self, path, method);
    }
};
