const std = @import("std");

const Token = struct {
    raw: []const u8,
    ival: ?i64 = null,
    fval: ?f64 = null,
    ty: TokenType,
};

const TokenType = enum {
    String,
    Number,
    Boolean,
    Null,
    Colon,
    Comma,
    CurlyBraceOpen,
    CurlyBraceClose,
    BracketOpen,
    BracketClose,
};

fn parse(raw_json: []const u8) !void {
    std.debug.print("json: {s}\n", .{raw_json});
    return;
}

fn isEscaped(s: []const u8) bool {
    return std.mem.eql(u8, s, "\\\"");
}

const Tokenizer = struct {
    allocator: std.mem.Allocator,
    raw_str: []const u8,
    state: *State,

    const State = struct {
        l: usize = 0,
        r: usize = 0,
        inside_string: bool = false,
        reading_null: bool = false,

        pub fn skip(self: *State) void {
            self.l += 1;
            self.r += 1;
        }

        pub fn alignlr(self: *State) void {
            self.l = self.r;
        }
    };

    pub fn init(
        allocator: std.mem.Allocator,
        raw_str: []const u8,
    ) !Tokenizer {
        var state = try allocator.create(State);
        state.* = State{};

        return Tokenizer{
            .allocator = allocator,
            .raw_str = raw_str,
            .state = state,
        };
    }

    pub fn deinit(self: *Tokenizer) void {
        self.allocator.destroy(self.state);
    }

    fn isEOL(self: Tokenizer) bool {
        return self.raw_str.len <= self.state.r;
    }

    fn current(self: Tokenizer) u8 {
        return self.raw_str[self.state.r];
    }

    fn next(self: Tokenizer) u8 {
        return self.raw_str[self.state.r + 1];
    }

    fn slice(self: Tokenizer) []const u8 {
        return self.raw_str[self.state.l..self.state.r];
    }

    // tokenize parses tokens and returns slice of Token.
    // caller owns the returned memory.
    pub fn tokenize(self: *Tokenizer) ![]const Token {
        var arr = try self.allocator.create(std.ArrayList(Token));
        defer self.allocator.destroy(arr);

        arr.* = std.ArrayList(Token).init(self.allocator);
        defer arr.deinit();

        try self.populate(arr);
        return arr.toOwnedSlice();
    }

    fn readNumber(self: Tokenizer) !Token {
        var is_num = true;
        var is_float = false;
        while (self.raw_str.len > self.state.r and is_num) {
            const c = self.current();
            if (!std.ascii.isDigit(c)) {
                if (c == '.') {
                    if (is_float) {
                        std.log.err("invalid token ({c}) at position {d}", .{ c, self.state.r });
                        return error.InvalidToken;
                    }
                    is_float = true;
                } else {
                    is_num = false;
                    break;
                }
            }

            self.state.r += 1;
        }

        const r = self.slice();
        return Token{
            .ty = .Number,
            .raw = r,
            .ival = if (!is_float) try std.fmt.parseInt(i64, r, 10) else null,
            .fval = if (is_float) try std.fmt.parseFloat(f64, r) else null,
        };
    }

    fn readNull(self: Tokenizer) !Token {
        if (self.raw_str.len < self.state.r + 3) {
            std.log.err("invalid token at position {d}", .{self.state.r});
            return error.InvalidToken;
        }

        const n = self.raw_str[self.state.r .. self.state.r + 4];
        self.state.r += 3;

        if (std.mem.eql(u8, n, "null")) {
            return Token{
                .ty = .Null,
                .raw = "null",
            };
        } else {
            std.log.err("invalid token ({s}) at position {d}", .{ n, self.state.r });
            return error.InvalidToken;
        }
    }

    fn populate(self: *Tokenizer, arr: *std.ArrayList(Token)) !void {
        while (!self.isEOL()) {
            const c = self.current();
            if (!self.state.inside_string) {
                switch (c) {
                    ' ' => {}, // ignore
                    '"' => self.state.inside_string = true,
                    '+', '-', '0'...'9' => {
                        self.state.r += 1;
                        try arr.append(try self.readNumber());
                    },
                    'n' => try arr.append(try self.readNull()),
                    '{' => try arr.append(Token{ .ty = .CurlyBraceOpen, .raw = "{" }),
                    '}' => try arr.append(Token{ .ty = .CurlyBraceClose, .raw = "}" }),
                    ':' => try arr.append(Token{ .ty = .Colon, .raw = ":" }),
                    ',' => try arr.append(Token{ .ty = .Comma, .raw = "," }),
                    else => {
                        std.log.err("invalid token ({c}) at position {d}", .{ c, self.state.r });
                        return error.InvalidToken;
                    },
                }

                self.state.r += 1;
                self.state.alignlr();
                continue;
            }

            if (c == '"' and !isEscaped(self.raw_str[self.state.r - 1 .. self.state.r + 1])) {
                // end of string
                try arr.append(Token{ .ty = .String, .raw = self.slice() });
                self.state.inside_string = false;
            }

            self.state.r += 1;
        }
    }
};

pub fn main() anyerror!void {
    std.debug.print("hello", .{});
}

test "tokenize test" {
    const testcases = &[_]struct {
        in: []const u8,
        want: []const Token = undefined,
        expectErr: bool = false,
        errType: anyerror = undefined,
    }{
        .{
            .in = "{\"hello\": \"world\"}",
            .want = comptime createTestTokens(Token{ .ty = .String, .raw = "world" }),
        },
        .{
            .in = "{\"hello\": \"\"}",
            .want = comptime createTestTokens(Token{ .ty = .String, .raw = "" }),
        },
        .{
            .in = "{\"hello\": null}",
            .want = comptime createTestTokens(Token{ .ty = .Null, .raw = "null" }),
        },
        .{
            .in = "{\"hello\": 10}",
            .want = comptime createTestTokens(Token{ .ty = .Number, .raw = "10", .ival = 10 }),
        },
        .{
            .in = "{\"hello\": +10}",
            .want = comptime createTestTokens(Token{ .ty = .Number, .raw = "+10", .ival = 10 }),
        },
        .{
            .in = "{\"hello\": -10}",
            .want = comptime createTestTokens(Token{ .ty = .Number, .raw = "-10", .ival = -10 }),
        },
        .{
            .in = "{\"hello\": 10.5}",
            .want = comptime createTestTokens(Token{ .ty = .Number, .raw = "10.5", .fval = 10.5 }),
        },
        .{
            .in = "{\"hello\": +10.5}",
            .want = comptime createTestTokens(Token{ .ty = .Number, .raw = "+10.5", .fval = 10.5 }),
        },
        .{
            .in = "{\"hello\": -10.5}",
            .want = comptime createTestTokens(Token{ .ty = .Number, .raw = "-10.5", .fval = -10.5 }),
        },
        .{
            .in = "{\"hello\": 0.0}",
            .want = comptime createTestTokens(Token{ .ty = .Number, .raw = "0.0", .fval = -0.0 }),
        },
        .{
            .in = "{\"hello\": \"world\", \"hello2\": \"world2\"}",
            .want = &[_]Token{
                .{ .ty = .CurlyBraceOpen, .raw = "{" },
                .{ .ty = .String, .raw = "hello" },
                .{ .ty = .Colon, .raw = ":" },
                .{ .ty = .String, .raw = "world" },
                .{ .ty = .Comma, .raw = "," },
                .{ .ty = .String, .raw = "hello2" },
                .{ .ty = .Colon, .raw = ":" },
                .{ .ty = .String, .raw = "world2" },
                .{ .ty = .CurlyBraceClose, .raw = "}" },
            },
        },
        .{
            .in = "{\"hello\": { \"world\": 10 } }",
            .want = &[_]Token{
                .{ .ty = .CurlyBraceOpen, .raw = "{" },
                .{ .ty = .String, .raw = "hello" },
                .{ .ty = .Colon, .raw = ":" },
                .{ .ty = .CurlyBraceOpen, .raw = "{" },
                .{ .ty = .String, .raw = "world" },
                .{ .ty = .Colon, .raw = ":" },
                .{ .ty = .Number, .raw = "10", .ival = 10 },
                .{ .ty = .CurlyBraceClose, .raw = "}" },
                .{ .ty = .CurlyBraceClose, .raw = "}" },
            },
        },
        .{ .in = "{\"hello\": 0.0.0}", .expectErr = true, .errType = error.InvalidToken },
        .{ .in = "{\"hello\": hello}", .expectErr = true, .errType = error.InvalidToken },
        .{ .in = "{hello: world}", .expectErr = true, .errType = error.InvalidToken },
        .{ .in = "{100: hello}", .expectErr = true, .errType = error.InvalidToken },
        .{ .in = "{\"hello\": nul}", .expectErr = true, .errType = error.InvalidToken },
    };

    for (testcases) |tc, ti| {
        std.log.warn("test case #{d}", .{ti + 1});
        var tokenizer = try Tokenizer.init(std.testing.allocator, tc.in);
        defer tokenizer.deinit();
        if (tc.expectErr) {
            try std.testing.expectError(tc.errType, tokenizer.tokenize());
            continue;
        }
        const result = try tokenizer.tokenize();
        defer std.testing.allocator.free(result);

        for (result) |r, i| {
            try std.testing.expectEqual(r.ty, tc.want[i].ty);
            try std.testing.expectEqualSlices(u8, r.raw, tc.want[i].raw);
            if (r.ival) |v| try std.testing.expectEqual(v, tc.want[i].ival.?);
            if (r.fval) |v| try std.testing.expectEqual(v, tc.want[i].fval.?);
        }
    }
}

fn createTestTokens(v: Token) []const Token {
    return &[_]Token{
        .{ .ty = .CurlyBraceOpen, .raw = "{" },
        .{ .ty = .String, .raw = "hello" },
        .{ .ty = .Colon, .raw = ":" },
        v,
        .{ .ty = .CurlyBraceClose, .raw = "}" },
    };
}
