const std = @import("std");
const http = std.http;

const CLIENTSECRETS_LOCATION = "./dsk.json";
const REDIRECT_URI = "<YOUR_REGISTERED_REDIRECT_URI>";
const SCOPES = .{
    "https://www.googleapis.com/auth/gmail.settings.basic",
    "https://www.googleapis.com/auth/gmail.labels",
};

const Creds = struct {
    client_id: []u8,
    project_id: []u8,
    auth_uri: []u8,
    token_uri: []u8,
    auth_provider_x509_cert_url: []u8,
    client_secret: []u8,
    redirect_uris: [][]u8,
};
const CredsDTO = struct { installed: struct {
    client_id: []u8,
    project_id: []u8,
    auth_uri: []u8,
    token_uri: []u8,
    auth_provider_x509_cert_url: []u8,
    client_secret: []u8,
    redirect_uris: [][]u8,
} };
pub fn main() !void {
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});

    var allocator = std.heap.GeneralPurposeAllocator(.{}){};
    defer {}
    // const client = http.Client{ .allocator = allocator };
    var creds: [1024]u8 = undefined;
    var path: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const realpath = try std.fs.realpath(CLIENTSECRETS_LOCATION, &path);

    std.debug.print("path {s}", .{realpath});
    const credsFile = try std.fs.openFileAbsolute(realpath, .{});
    const len = try credsFile.read(&creds);

    std.debug.print("file\n {s}", .{creds[0 .. len - 1]});
    const parsed = try std.json.parseFromSlice(CredsDTO, allocator.allocator(), creds[0 .. len - 1], .{ .ignore_unknown_fields = true });
    const credsParsed: Creds = .{
        .auth_uri = parsed.value.installed.auth_uri,
        .token_uri = parsed.value.installed.token_uri,
        .project_id = parsed.value.installed.project_id,
        .client_secret = parsed.value.installed.client_secret,
        .redirect_uris = parsed.value.installed.redirect_uris,
        .auth_provider_x509_cert_url = parsed.value.installed.auth_provider_x509_cert_url,
        .client_id = parsed.value.installed.client_id,
    };
    std.debug.print("parsed\n {s}", .{credsParsed.client_id});

    // const req = try client.open(http.Method.GET, "", .{});
    // try req.send();
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
