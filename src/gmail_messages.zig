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

const MAX_PARTS = 10; // Adjust this value based on your expected maximum number of parts

pub const MessageValue = struct {
    parts: [MAX_PARTS][]const u8,
    parts_count: usize,
    body: []const u8,
};

pub fn listEmails(self: *Gmail) !std.ArrayList(MessageValue) {
    const path = "/gmail/v1/users/me/messages";

    var response_buffer = try self.sendAuthenticatedRequest(path, .GET);
    defer response_buffer.deinit();

    const response = response_buffer.items;
    const parsed = try std.json.parseFromSlice(MessagesResponse, self.allocator.*, response, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    var message_values = std.ArrayList(MessageValue).init(self.allocator.*);

    for (parsed.value.messages[0..10]) |message| {
        var mpath: [60]u8 = undefined;
        const mpath_str = try std.fmt.bufPrint(&mpath, "/gmail/v1/users/me/messages/{s}", .{message.id});
        var message_response_buffer = try self.sendAuthenticatedRequest(mpath_str, .GET);
        defer message_response_buffer.deinit();
        var messageValue: MessageValue = .{
            .parts = undefined,
            .parts_count = 0,
            .body = undefined,
        };
        const message_response = message_response_buffer.items;
        const parsed_message = try std.json.parseFromSlice(GmailMessage, self.allocator.*, message_response, .{ .ignore_unknown_fields = true, .allocate = .alloc_always });
        defer parsed_message.deinit();
        if (parsed_message.value.payload.?.body.?.data) |data| {
            const decoded = decodeBase64Url(self.allocator.*, data) catch |err| {
                std.debug.print("Error decoding base64url: {}\n", .{err});
                return error.DecodingError;
            };
            defer self.allocator.free(decoded);
            messageValue.body = decoded;
        }
        if (parsed_message.value.payload.?.parts) |parts| {
            for (parts) |part| {
                if (part.body.?.data) |data| {
                    if (messageValue.parts_count >= MAX_PARTS) {
                        std.debug.print("Warning: Exceeded maximum number of parts\n", .{});
                        break;
                    }
                    const decoded = decodeBase64Url(self.allocator.*, data) catch |err| {
                        std.debug.print("Error decoding base64url: {}\n", .{err});
                        return error.DecodingError;
                    };
                    defer self.allocator.free(decoded);
                    messageValue.parts[messageValue.parts_count] = decoded;
                    messageValue.parts_count += 1;
                }
            }
        }
        try message_values.append(messageValue);
    }
    return message_values;
}

fn decodeBase64Url(allocator: std.mem.Allocator, encoded: []const u8) ![]const u8 {
    const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_".*;
    const base64url = std.base64.Base64Decoder.init(alphabet, '=');

    const max_len = try base64url.calcSizeForSlice(encoded);

    var decoded = try allocator.alloc(u8, max_len);
    errdefer allocator.free(decoded);

    try base64url.decode(decoded[0..], encoded);
    return std.mem.trimRight(u8, try allocator.realloc(decoded, encoded.len), "");
}
