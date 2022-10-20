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
    DoubleQuote,
    Colon,
    Comma,
    CurlyBraceOpen,
    CurlyBraceClose,
    BracketOpen,
    BracketClose,
    EOL,
};

fn parse(raw_json: []const u8) !void {
    std.debug.print("json: {s}\n", .{raw_json});
    return;
}

fn isEscaped(s: []const u8) bool {
    return std.mem.eql(u8, s, "\\\"");
}

fn isSignedNum(raw_str: []const u8, pos: usize) bool {
    if (raw_str.len <= pos + 1) {
        return false;
    }

    const c = raw_str[pos];
    if (c == '+' or c == '-') {
        if (std.ascii.isDigit(raw_str[pos + 1])) {
            return true;
        }
    }

    return false;
}

fn tokenize(allocator: std.mem.Allocator, raw_str: []const u8) !*std.ArrayList(Token) {
    var arr = try allocator.create(std.ArrayList(Token));
    arr.* = std.ArrayList(Token).init(allocator);

    var l: usize = 0;
    var r: usize = 0;
    var inside_double_quote = false;
    while (raw_str.len > r) {
        const c = raw_str[r];
        if (!inside_double_quote and std.ascii.isSpace(c)) {
            l += 1;
            r += 1;
            continue;
        }
        if (inside_double_quote and c != '"') {
            r += 1;
            continue;
        }

        if (!inside_double_quote and (std.ascii.isDigit(c) or isSignedNum(raw_str, r))) {
            var is_num = true;
            var is_float = false;
            while (raw_str.len > r and is_num) {
                const n = raw_str[r];
                if (n == ',' or n == '}' or n == ' ') {
                    is_num = false;
                    break;
                }

                if (raw_str[r] == '.') {
                    if (is_float) return error.InvalidFloat;
                    is_float = true;
                }
                r += 1;
            }

            std.debug.print("{s}\n", .{raw_str[l..r]});
            try arr.append(Token{
                .ty = .Number,
                .raw = raw_str[l..r],
                .ival = if (!is_float) try std.fmt.parseInt(i64, raw_str[l..r], 10) else null,
                .fval = if (is_float) try std.fmt.parseFloat(f64, raw_str[l..r]) else null,
            });
            l = r;
            continue;
        }

        switch (c) {
            '{' => try arr.append(Token{ .ty = .CurlyBraceOpen, .raw = "{" }),
            '}' => try arr.append(Token{ .ty = .CurlyBraceClose, .raw = "}" }),
            '"' => {
                if (inside_double_quote) {
                    if (isEscaped(raw_str[r - 1 .. r + 1])) {
                        r += 1;
                        continue;
                    }
                    // end of string
                    try arr.append(Token{ .ty = .String, .raw = raw_str[l..r] });
                }
                inside_double_quote = !inside_double_quote;
                try arr.append(Token{ .ty = .DoubleQuote, .raw = "\"" });
            },
            ':' => try arr.append(Token{ .ty = .Colon, .raw = ":" }),
            ',' => try arr.append(Token{ .ty = .Comma, .raw = "," }),
            else => {
                r += 1;
                continue;
            },
        }

        r += 1;
        l = r;
    }

    return arr;
}

pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const arr = try tokenize(arena.allocator(), " { \"'he\\\"l lo'\":\"{world}\", \"i\": -10 , \"f\": 10.5 }");

    for (arr.items) |a, i| {
        std.debug.print("{d}th type={}, raw={s}\n", .{ i, a.ty, a.raw });
    }
}

test "tokenize test" {
    const testcases = &[_]struct {
        in: []const u8,
        want: []const Token,
        expectErr: bool = false,
    }{.{ .in = "{\"hello\": \"world\"}", .want = &[_]Token{
        .{ .ty = .CurlyBraceOpen, .raw = "{" },
        .{ .ty = .DoubleQuote, .raw = "\"" },
        .{ .ty = .String, .raw = "hello" },
        .{ .ty = .DoubleQuote, .raw = "\"" },
        .{ .ty = .Colon, .raw = ":" },
        .{ .ty = .DoubleQuote, .raw = "\"" },
        .{ .ty = .String, .raw = "world" },
        .{ .ty = .DoubleQuote, .raw = "\"" },
        .{ .ty = .CurlyBraceClose, .raw = "}" },
    } }};

    for (testcases) |tc| {
        const res = try tokenize(std.testing.allocator, tc.in);
        defer std.testing.allocator.destroy(res);
        defer res.deinit();

        const result = res.items;
        for (result) |r, i| {
            try std.testing.expectEqual(r.ty, tc.want[i].ty);
            try std.testing.expectEqualSlices(u8, r.raw, tc.want[i].raw);
        }
    }
}
