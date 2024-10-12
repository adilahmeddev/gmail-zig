const std = @import("std");
const Gmail = @import("gmail.zig").Gmail;

pub const Header = struct {
    name: []const u8,
    value: []const u8,
};

pub const Body = struct {
    attachmentId: ?[]const u8 = null,
    size: ?u64 = null,
    data: ?[]const u8 = null,
};

pub const Payload = struct {
    partId: ?[]const u8 = null,
    mimeType: ?[]const u8 = null,
    filename: ?[]const u8 = null,
    headers: ?[]Header = null,
    body: ?Body = null,
    parts: ?[]Payload = null,
};

pub const GmailMessage = struct {
    id: ?[]const u8 = null,
    threadId: ?[]const u8 = null,
    labelIds: ?[][]const u8 = null,
    snippet: ?[]const u8 = null,
    historyId: ?[]const u8 = null,
    internalDate: ?[]const u8 = null,
    payload: ?Payload = null,
    sizeEstimate: ?u32 = null,
};

const MessagesResponse = struct {
    messages: []Message,
};

const Message = struct {
    id: []u8,
    threadId: []u8,
};

pub fn listEmails(self: *Gmail) !void {
    // Prepare the request URL
    const path = "/gmail/v1/users/me/messages";

    // Send the GET request
    var response_buffer = try self.sendAuthenticatedRequest(path, .GET);
    defer response_buffer.deinit();

    // Parse and print the response
    const response = response_buffer.items;
    std.debug.print("Response: {s}\n", .{response});
    const parsed = try std.json.parseFromSlice(MessagesResponse, self.allocator.*, response, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    for (parsed.value.messages[0..10]) |message| {
        var mpath: [60]u8 = undefined;
        const mpath_str = try std.fmt.bufPrint(&mpath, "/gmail/v1/users/me/messages/{s}", .{message.id});
        var message_response_buffer = try self.sendAuthenticatedRequest(mpath_str, .GET);
        defer message_response_buffer.deinit();

        // Parse and print the response
        const message_response = message_response_buffer.items;
        std.debug.print("Response: {s}\n", .{message_response});
        const parsed_message = try std.json.parseFromSlice(GmailMessage, self.allocator.*, message_response, .{ .ignore_unknown_fields = true, .allocate = .alloc_always });
        defer parsed_message.deinit();
        if (parsed_message.value.payload.?.body.?.data) |data| {
            const decoded = decodeBase64Url(self.allocator.*, data) catch |err| {
                std.debug.print("Error decoding base64url: {}\n", .{err});
                return;
            };
            defer self.allocator.free(decoded);
            std.debug.print("\n\n\n\n\ndecoded: {s}\n\n\n\n\n", .{decoded});
        }
    }
}

fn decodeBase64Url(allocator: std.mem.Allocator, encoded: []const u8) ![]u8 {
    // Define the base64url alphabet
    const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_".*;
    const base64url = std.base64.Base64Decoder.init(alphabet, '=');

    // Calculate the maximum possible decoded length
    const max_len = try base64url.calcSizeForSlice(encoded);

    // Allocate buffer for decoded data
    var decoded = try allocator.alloc(u8, max_len);
    errdefer allocator.free(decoded);

    // Perform the decoding
    try base64url.decode(decoded[0..], encoded);

    // Shrink the buffer to the actual decoded length
    return allocator.realloc(decoded, encoded.len);
}
