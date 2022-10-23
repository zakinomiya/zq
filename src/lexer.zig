const std = @import("std"); 

pub const Node = struct {
    key: []const u8,
    value: *Node,
};

pub const ValueType = enum {
    Null,
    Number,
    String,
    Object,
    Array,
};

pub const TokenType = enum {
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

pub const NumValue = union(enum) {
    integer: i64,
    float: f64,
};

pub const Token = struct {
    raw: []const u8,
    num_val: ?NumValue = null,
    pos: usize,
    ty: TokenType,

    pub fn newString(pos: usize, raw: []const u8) Token {
        return Token{
            .ty = .String,
            .pos = pos,
            .raw = raw,
        };
    }

    pub fn newInt(pos: usize, val: i64, raw: []const u8) Token {
        return Token{
            .ty = .Number,
            .num_val = NumValue{ .integer = val },
            .pos = pos,
            .raw = raw,
        };
    }

    pub fn newFloat(pos: usize, val: f64, raw: []const u8) Token {
        return Token{
            .ty = .Number,
            .num_val = NumValue{ .float = val },
            .pos = pos,
            .raw = raw,
        };
    }

    pub fn newBool(pos: usize, val: bool) Token {
        return Token{
            .raw = if (val) "true" else "false",
            .pos = pos,
            .ty = .Boolean,
        };
    }

    pub fn newNull(pos: usize) Token {
        return Token{
            .raw = "null",
            .pos = pos,
            .ty = .Null,
        };
    }

    pub fn newColon(pos: usize) Token {
        return Token{
            .raw = ":",
            .pos = pos,
            .ty = .Colon,
        };
    }

    pub fn newComma(pos: usize) Token {
        return Token{
            .raw = ",",
            .pos = pos,
            .ty = .Comma,
        };
    }

    pub fn newCurlyOpen(pos: usize) Token {
        return Token{
            .raw = "{",
            .pos = pos,
            .ty = .CurlyBraceOpen,
        };
    }

    pub fn newCurlyClose(pos: usize) Token {
        return Token{
            .raw = "}",
            .pos = pos,
            .ty = .CurlyBraceClose,
        };
    }

    pub fn newBracketOpen(pos: usize) Token {
        return Token{
            .raw = "[",
            .pos = pos,
            .ty = .BracketOpen,
        };
    }

    pub fn newBracketClose(pos: usize) Token {
        return Token{
            .raw = "]",
            .pos = pos,
            .ty = .BracketClose,
        };
    }
};

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
                        std.log.info("invalid token ({c}) at position {d}", .{ c, self.state.r });
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
        return if (is_float)
            Token.newFloat(self.state.l, try std.fmt.parseFloat(f64, r), r)
        else
            Token.newInt(self.state.l, try std.fmt.parseInt(i64, r, 10), r);
    }

    fn readNull(self: Tokenizer) !Token {
        if (self.raw_str.len < self.state.r + 3) {
            std.log.info("invalid token at position {d}", .{self.state.r});
            return error.InvalidToken;
        }

        const n = self.raw_str[self.state.r .. self.state.r + 4];
        self.state.r += 3;

        if (std.mem.eql(u8, n, "null")) {
            return Token.newNull(self.state.l);
        } else {
            std.log.info("invalid token ({s}) at position {d}", .{ n, self.state.r });
            return error.InvalidToken;
        }
    }

    fn read(self: *Tokenizer, c: u8) !?Token {
        return switch (c) {
            ' ' => null, // ignore
            '"' => {
                self.state.inside_string = true;
                return null;
            },
            '+', '-', '0'...'9' => {
                self.state.r += 1;
                const t = try self.readNumber();
                self.state.r -= 1;
                return t;
            },
            'n' => try self.readNull(),
            '[' => Token.newBracketOpen(self.state.l),
            ']' => Token.newBracketClose(self.state.l),
            '{' => Token.newCurlyOpen(self.state.l),
            '}' => Token.newCurlyClose(self.state.l),
            ':' => Token.newColon(self.state.l),
            ',' => Token.newComma(self.state.l),
            else => {
                std.log.info("invalid token ({c}) at position {d}", .{ c, self.state.r });
                return error.InvalidToken;
            },
        };
    }

    fn populate(self: *Tokenizer, arr: *std.ArrayList(Token)) !void {
        while (!self.isEOL()) {
            const c = self.current();
            if (!self.state.inside_string) {
                if (try self.read(c)) |tok| {
                    try arr.append(tok);
                }

                self.state.r += 1;
                self.state.alignlr();
                continue;
            }

            if (c == '"' and !isEscaped(self.raw_str[self.state.r - 1 .. self.state.r + 1])) {
                // end of string
                try arr.append(Token.newString(self.state.l, self.slice()));
                self.state.inside_string = false;
                self.state.r += 1;
                self.state.alignlr();
            } else {
                self.state.r += 1;
            }
        }
    }
};

test "tokenize test" {
    const TestCase = struct {
        in: []const u8,
        want: []const Token = undefined,
        expectErr: bool = false,
        errType: anyerror = undefined,
    };

    const testcases = &[_]TestCase{
        .{
            .in = "{\"hello\":\"world\"}",
            .want = comptime createTestTokens(.{ .raw = "world", .pos = 10, .ty = .String }),
        },
        .{
            .in = "{\"hello\":\"\"}",
            .want = comptime createTestTokens(.{ .raw = "", .pos = 10, .ty = .String }),
        },
        .{
            .in = "{\"hello\":null}",
            .want = comptime createTestTokens(.{ .raw = "null", .pos = 9, .ty = .Null }),
        },
        .{
            .in = "{\"hello\":10}",
            .want = comptime createTestTokens(.{ .raw = "10", .pos = 9, .ty = .Number, .num_val = NumValue{ .integer = 10 } }),
        },
        .{
            .in = "{\"hello\":+10}",
            .want = comptime createTestTokens(.{ .raw = "+10", .pos = 9, .ty = .Number, .num_val = NumValue{ .integer = 10 } }),
        },
        .{
            .in = "{\"hello\":-10}",
            .want = comptime createTestTokens(.{ .raw = "-10", .pos = 9, .ty = .Number, .num_val = NumValue{ .integer = -10 } }),
        },
        .{
            .in = "{\"hello\":10.5}",
            .want = comptime createTestTokens(.{ .raw = "10.5", .pos = 9, .ty = .Number, .num_val = NumValue{ .float = 10.5 } }),
        },
        .{
            .in = "{\"hello\":+10.5}",
            .want = comptime createTestTokens(.{ .raw = "+10.5", .pos = 9, .ty = .Number, .num_val = NumValue{ .float = 10.5 } }),
        },
        .{
            .in = "{\"hello\":-10.5}",
            .want = comptime createTestTokens(.{ .raw = "-10.5", .pos = 9, .ty = .Number, .num_val = NumValue{ .float = -10.5 } }),
        },
        .{
            .in = "{\"hello\":0.0}",
            .want = comptime createTestTokens(.{ .raw = "0.0", .pos = 9, .ty = .Number, .num_val = NumValue{ .float = 0.0 } }),
        },

        .{
            .in = "{\"hello\":\"world\",\"hello2\":\"world2\"}",
            .want = &[_]Token{
                .{ .ty = .CurlyBraceOpen, .pos = 0, .raw = "{" },
                .{ .ty = .String, .pos = 2, .raw = "hello" },
                .{ .ty = .Colon, .pos = 8, .raw = ":" },
                .{ .ty = .String, .pos = 10, .raw = "world" },
                .{ .ty = .Comma, .pos = 16, .raw = "," },
                .{ .ty = .String, .pos = 18, .raw = "hello2" },
                .{ .ty = .Colon, .pos = 25, .raw = ":" },
                .{ .ty = .String, .pos = 27, .raw = "world2" },
                .{ .ty = .CurlyBraceClose, .pos = 34, .raw = "}" },
            },
        },
        .{
            .in = "{\"hello\":{\"world\":10}}",
            .want = &[_]Token{
                .{ .ty = .CurlyBraceOpen, .pos = 0, .raw = "{" },
                .{ .ty = .String, .pos = 2, .raw = "hello" },
                .{ .ty = .Colon, .pos = 8, .raw = ":" },
                .{ .ty = .CurlyBraceOpen, .pos = 9, .raw = "{" },
                .{ .ty = .String, .pos = 11, .raw = "world" },
                .{ .ty = .Colon, .pos = 17, .raw = ":" },
                .{ .ty = .Number, .pos = 18, .raw = "10", .num_val = NumValue{ .integer = 10 } },
                .{ .ty = .CurlyBraceClose, .pos = 20, .raw = "}" },
                .{ .ty = .CurlyBraceClose, .pos = 21, .raw = "}" },
            },
        },
        .{
            .in = "{\"hello\":[\"world\",\"!!\"]}",
            .want = &[_]Token{
                .{ .ty = .CurlyBraceOpen, .pos = 0, .raw = "{" },
                .{ .ty = .String, .pos = 2, .raw = "hello" },
                .{ .ty = .Colon, .pos = 8, .raw = ":" },
                .{ .ty = .BracketOpen, .pos = 9, .raw = "[" },
                .{ .ty = .String, .pos = 11, .raw = "world" },
                .{ .ty = .Comma, .pos = 17, .raw = "," },
                .{ .ty = .String, .pos = 19, .raw = "!!" },
                .{ .ty = .BracketClose, .pos = 22, .raw = "]" },
                .{ .ty = .CurlyBraceClose, .pos = 23, .raw = "}" },
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
            try std.testing.expectEqual(tc.want[i].ty, r.ty);
            try std.testing.expectEqual(tc.want[i].pos, r.pos);
            try std.testing.expectEqualSlices(u8, tc.want[i].raw, r.raw);
            if (r.num_val) |v| {
                try std.testing.expectEqual(v, tc.want[i].num_val.?);
            }
        }
    }
}

fn createTestTokens(v: Token) []const Token {
    return &[_]Token{
        .{ .ty = .CurlyBraceOpen, .pos = 0, .raw = "{" },
        .{ .ty = .String, .pos = 2, .raw = "hello" },
        .{ .ty = .Colon, .pos = 8, .raw = ":" },
        v,
        .{ .ty = .CurlyBraceClose, .pos = if (v.ty == .String) v.pos + v.raw.len + 1 else v.pos + v.raw.len, .raw = "}" },
    };
}
