const std = @import("std");
const Gmail = @import("gmail.zig").Gmail;
const http = std.http;

pub fn main() !void {
    var a = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = &a.allocator();
    defer _ = a.deinit();

    var gmail = Gmail.init(allocator);

    try gmail.authenticate();
    const emails = try gmail.listEmails();
    defer emails.deinit();
    defer allocator.free(emails.items);

    std.debug.print("Emails: {any}\n", .{emails.items[0]});
}
