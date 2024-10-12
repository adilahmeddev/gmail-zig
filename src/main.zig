const std = @import("std");
const Gmail = @import("gmail.zig").Gmail;
const http = std.http;

pub fn main() !void {
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});

    var allocator = std.heap.GeneralPurposeAllocator(.{}){};

    var gmail = Gmail.init(&allocator.allocator());
    try gmail.authenticate();

    try gmail.listEmails();

    // const req = try http.client.open(http.Method.GET, "", .{});
    // try req.send();
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
