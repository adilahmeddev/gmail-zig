const std = @import("std");
const zap = @import("zap");
const builtin = @import("builtin");

const testing = std.testing;

const CLIENTSECRETS_LOCATION = "./gmail.json";
const REDIRECT_URI = "http://localhost:8888";
const SCOPE = "https://www.googleapis.com/auth/gmail.readonly";
const Creds = struct {
    client_id: []u8,
    project_id: []u8,
    auth_uri: []u8,
    token_uri: []u8,
    auth_provider_x509_cert_url: []u8,
    client_secret: []u8,
    redirect_uris: [][]u8,
};
const CredsDTO = struct {
    installed: struct {
        client_id: []u8,
        project_id: []u8,
        auth_uri: []u8,
        token_uri: []u8,
        auth_provider_x509_cert_url: []u8,
        client_secret: []u8,
        redirect_uris: [][]u8,
    },
};
var code: []const u8 = undefined;
pub const Gmail = struct {
    const Self = @This();
    allocator: *const std.mem.Allocator,

    pub fn init(allocator: *const std.mem.Allocator) Self {
        return Self{ .allocator = allocator };
    }
    fn openUrl(url: []const u8) !void {
        const allocator = std.heap.page_allocator;

        switch (builtin.os.tag) {
            .windows => {
                const command = try std.fmt.allocPrint(allocator, "start {s}", .{url});
                defer allocator.free(command);
                try std.process.execToNull(allocator, &.{ "cmd", "/C", command });
            },
            .macos => {
                try std.process.execToNull(allocator, &.{ "open", url });
            },
            .linux => {
                var proc = std.process.Child.init(&.{ "dbus-launch", "--auto-syntax", "xdg-open", url }, allocator);
                proc.stdin_behavior = .Ignore;
                proc.stdout_behavior = .Ignore;
                proc.stderr_behavior = .Ignore;

                _ = try proc.spawnAndWait();
                _ = try proc.kill();
            },
            else => {
                std.debug.print("Unsupported operating system\n", .{});
                return error.UnsupportedOS;
            },
        }
    }

    fn handleRequest(self: *Self) !void {
        const Handler = struct {
            var alloc: std.mem.Allocator = undefined;

            pub fn on_request(r: zap.Request) void {
                std.debug.print("\n=====================================================\n", .{});
                defer std.debug.print("=====================================================\n\n", .{});

                // check for query parameters
                r.parseQuery();

                const param_count = r.getParamCount();
                std.log.info("param_count: {}", .{param_count});

                // ================================================================
                // Access RAW params from querystring
                // ================================================================

                // let's get param "one" by name
                std.debug.print("\n", .{});
                if (r.getParamStr(alloc, "code", false)) |maybe_str| {
                    if (maybe_str) |*s| {
                        defer s.deinit();
                        code = s.str;
                        std.log.info("Param code = {s}", .{s.str});
                    } else {
                        std.log.info("Param code not found!", .{});
                    }
                }
                // since we provided "false" for duplicating strings in the call
                // to getParamStr(), there won't be an allocation error
                else |err| {
                    std.log.err("cannot check for `code` param: {any}\n", .{err});
                }

                // check if we received a terminate=true parameter

                zap.stop();
            }
        };

        Handler.alloc = self.allocator.*;

        // setup listener
        var listener = zap.HttpListener.init(
            .{
                .port = 8888,
                .on_request = Handler.on_request,
                .log = true,
                .max_clients = 10,
                .max_body_size = 1 * 1024,
            },
        );
        zap.enableDebugLog();
        try listener.listen();
        // std.log.info("\n\nListening on {s}\n", .{listener.url});

        std.log.info("\n\nTerminate with CTRL+C or by sending query param terminate=true\n", .{});

        zap.start(.{
            .threads = 1,
            .workers = 1,
        });
    }
    pub fn getAuthCode(self: *Self) !void {
        var buffer: [1024]u8 = undefined;
        var path: [std.fs.MAX_PATH_BYTES]u8 = undefined;

        const realpath = try std.fs.realpath(CLIENTSECRETS_LOCATION, &path);

        std.debug.print("path {s}", .{realpath});

        if (std.fs.openFileAbsolute(realpath, .{})) |file| {
            const len = try file.read(&buffer);

            std.debug.print("file\n {s}", .{buffer[0 .. len - 1]});
            const parsed = try std.json.parseFromSlice(CredsDTO, self.allocator.*, buffer[0..len], .{ .ignore_unknown_fields = true });
            const creds: Creds = .{
                .auth_uri = parsed.value.installed.auth_uri,
                .token_uri = parsed.value.installed.token_uri,
                .project_id = parsed.value.installed.project_id,
                .client_secret = parsed.value.installed.client_secret,
                .redirect_uris = parsed.value.installed.redirect_uris,
                .auth_provider_x509_cert_url = parsed.value.installed.auth_provider_x509_cert_url,
                .client_id = parsed.value.installed.client_id,
            };

            std.debug.print("parsed\n {s}", .{creds.client_id});

            const url = try std.fmt.allocPrint(self.allocator.*, "{s}?response_type=code&redirect_uri={s}&scope={s}&client_id={s}", .{
                creds.auth_uri,
                creds.redirect_uris[0],
                SCOPE,

                creds.client_id,
            });
            std.debug.print("\n\n\n\nURL {s}\n\n\n", .{url});
            try openUrl(url);
            try self.handleRequest();
            std.debug.print("\n\n\n\nCODE {s}\n\n\n", .{code});
            try self.exchangeCodeForToken(creds, code);
        } else |err| {
            std.debug.panic("Error opening file: {}", .{err});
        }
    }

    fn exchangeCodeForToken(self: *Self, creds: Creds, auth_code: []const u8) !void {
        const allocator = self.allocator.*;

        // Prepare the request body
        const body = try std.fmt.allocPrint(allocator, "code={s}&client_id={s}&client_secret={s}&redirect_uri={s}&grant_type=authorization_code", .{
            auth_code,
            creds.client_id,
            creds.client_secret,
            REDIRECT_URI,
        });
        defer allocator.free(body);

        // Create a HTTP client
        var client = std.http.Client{ .allocator = allocator };
        defer client.deinit();

        // Prepare the request

        // Send the POST request
        var rb = std.ArrayList(u8).init(allocator);
        var server_header_buffer: [8192]u8 = undefined;
        const req = try client.fetch(.{
            .server_header_buffer = &server_header_buffer,
            .method = .POST,
            .location = .{ .uri = try std.Uri.parse(creds.token_uri) },
            .payload = body,
            .headers = .{ .content_type = .{ .override = "application/x-www-form-urlencoded" } },
            .response_storage = .{ .dynamic = &rb },
        });

        if (req.status != std.http.Status.ok) {
            std.debug.panic("Request failed: {}", .{req.status});
        }
        const response = rb.items;

        // Parse the JSON response
        const TokenResponse = struct {
            access_token: []const u8,
            expires_in: u32,
            refresh_token: []const u8,
            scope: []const u8,
            token_type: []const u8,
        };

        const parsed = try std.json.parseFromSlice(TokenResponse, allocator, response, .{});
        defer parsed.deinit();

        // Use the access token
        std.debug.print("\n\nAccess Token: {s}\n", .{parsed.value.access_token});
        std.debug.print("Expires In: {d} seconds\n", .{parsed.value.expires_in});
        std.debug.print("Refresh Token: {s}\n\n", .{parsed.value.refresh_token});

        // TODO: Store these tokens securely for future use
    }
};
