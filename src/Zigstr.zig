const std = @import("std");
const mem = std.mem;
const unicode = std.unicode;

const CowList = @import("cow_list").CowList;
const ascii = @import("ascii.zig");
const ziglyph = @import("ziglyph");
const CodePointIterator = ziglyph.CodePointIterator;
const Grapheme = ziglyph.Grapheme;
const GraphemeIterator = Grapheme.GraphemeIterator;
const prop_list = ziglyph.prop_list;

const Self = @This();

allocator: mem.Allocator,
list: CowList(u8),

/// fromConstBytes returns a new Zigstr from the byte slice `str`, which will *not* be freed on `deinit`.
pub fn fromConstBytes(allocator: mem.Allocator, str: []const u8) !Self {
    return Self{ .allocator = allocator, .list = CowList(u8).initConst(allocator, str) };
}

/// fromOwnedBytes returns a new Zigstr from the owned byte slice `str`, which will be freed on `deinit`.
pub fn fromOwnedBytes(allocator: mem.Allocator, str: []u8) !Self {
    return Self{ .allocator = allocator, .list = CowList(u8).initOwned(allocator, str) };
}

/// fromCodePoints returns a new Zigstr from `code points`.
pub fn fromCodePoints(allocator: mem.Allocator, code_points: []const u21) !Self {
    const ascii_only = blk_ascii: {
        break :blk_ascii for (code_points) |cp| {
            if (cp > 127) break false;
        } else true;
    };

    if (ascii_only) {
        return Self{
            .allocator = allocator,
            .list = blk_b: {
                var list = try std.ArrayList(u8).initCapacity(allocator, code_points.len);
                defer list.deinit();
                for (code_points) |cp| list.appendAssumeCapacity(@intCast(cp));
                break :blk_b CowList(u8).initOwned(allocator, try list.toOwnedSlice());
            },
        };
    } else {
        return Self{
            .allocator = allocator,
            .list = blk_b: {
                var list = std.ArrayList(u8).init(allocator);
                defer list.deinit();
                var cp_buf: [4]u8 = undefined;
                for (code_points) |cp| {
                    const len = try unicode.utf8Encode(cp, &cp_buf);
                    try list.appendSlice(cp_buf[0..len]);
                }
                break :blk_b CowList(u8).initOwned(allocator, try list.toOwnedSlice());
            },
        };
    }
}

test "Zigstr from code points" {
    var allocator = std.testing.allocator;
    const cp_array = [_]u21{ 0x68, 0x65, 0x6C, 0x6C, 0x6F }; // "hello"

    var str = try fromCodePoints(allocator, &cp_array);
    defer str.deinit();

    try expect(str.eql("hello"));
}

/// fromJoined returns a new Zigstr from the concatenation of strings in `slice` with `sep` separator.
pub fn fromJoined(allocator: mem.Allocator, slice: []const []const u8, sep: []const u8) !Self {
    return fromOwnedBytes(allocator, try mem.join(allocator, sep, slice));
}

test "Zigstr fromJoined" {
    var str = try fromJoined(std.testing.allocator, &[_][]const u8{ "Hello", "World" }, " ");
    defer str.deinit();

    try expect(str.eql("Hello World"));
}

pub fn deinit(self: *Self) void {
    self.list.deinit();
}

/// bytes returns a `[]const u8` of the bytes that make up this Zigstr.
pub fn bytes(self: Self) []const u8 {
    return self.list.asConstSlice();
}

/// toOwnedSlice returns the bytes of this Zigstr to be freed by caller. This Zigstr is reset to empty.
pub fn toOwnedSlice(self: *Self) ![]u8 {
    return self.list.toOwnedSlice();
}

test "Zigstr toOwnedSlice" {
    var allocator = std.testing.allocator;
    var str = try fromConstBytes(allocator, "Hello");
    defer str.deinit();

    try expect(str.eql("Hello"));
    const slice = try str.toOwnedSlice();
    defer allocator.free(slice);
    try expectEqualStrings(slice, "Hello");
    try expect(str.eql(""));
}

/// reset reinitializes this Zigstr from the byte slice `str`.
pub fn reset(self: *Self, str: []const u8) !void {
    var list = try self.list.asList();
    try list.replaceRange(0, list.items.len, str);
}

/// byteLen returns the number of bytes, which can be different from the number of code points and the
/// number of graphemes.
pub fn byteLen(self: Self) usize {
    return self.list.asConstSlice().len;
}

/// codePointIter returns a code point iterator based on the bytes of this Zigstr.
pub fn codePointIter(self: Self) CodePointIterator {
    return CodePointIterator{ .bytes = self.bytes() };
}

/// codePoints returns the code points that make up this Zigstr. Caller must free returned slice.
pub fn codePoints(self: *Self, allocator: mem.Allocator) ![]u21 {
    var code_points = try std.ArrayList(u21).initCapacity(allocator, self.byteLen());
    defer code_points.deinit();

    var iter = self.codePointIter();
    while (iter.next()) |cp| {
        code_points.appendAssumeCapacity(cp.scalar);
    }

    return code_points.toOwnedSlice();
}

/// codePointLen returns the number of code points, which can be different from the number of bytes
/// and the number of graphemes.
pub fn codePointLen(self: *Self) !usize {
    const cps = try self.codePoints(self.allocator);
    defer self.allocator.free(cps);
    return cps.len;
}

/// graphemeIter returns a grapheme cluster iterator based on the bytes of this Zigstr. Each grapheme
/// can be composed of multiple code points, so the next method returns a slice of bytes.
pub fn graphemeIter(self: *Self) anyerror!GraphemeIterator {
    return GraphemeIterator.init(self.bytes());
}

/// graphemes returns the grapheme clusters that make up this Zigstr. Caller must free returned slice.
pub fn graphemes(self: *Self, allocator: mem.Allocator) ![]Grapheme {
    // Cache miss, generate.
    var giter = try self.graphemeIter();
    var gcs = try std.ArrayList(Grapheme).initCapacity(allocator, self.byteLen());
    defer gcs.deinit();

    while (giter.next()) |gc| {
        gcs.appendAssumeCapacity(gc);
    }

    return gcs.toOwnedSlice();
}

/// graphemeLen returns the number of grapheme clusters, which can be different from the number of bytes
/// and the number of code points.
pub fn graphemeLen(self: *Self) !usize {
    const gcs = try self.graphemes(self.allocator);
    defer self.allocator.free(gcs);
    return gcs.len;
}

/// copy a Zigstr to a new Zigstr. Don't forget to to `deinit` the returned Zigstr.
pub fn copy(self: Self, allocator: mem.Allocator) !Self {
    return Self{
        .allocator = allocator,
        .list = b_blk: {
            var list = try std.ArrayList(u8).initCapacity(allocator, self.byteLen());
            defer list.deinit();
            list.appendSliceAssumeCapacity(self.bytes());
            break :b_blk CowList(u8).initOwned(allocator, try list.toOwnedSlice());
        },
    };
}

/// eql compares for exact byte per byte equality with `other`.
pub fn eql(self: Self, other: anytype) bool {
    const slice = self.bytes();

    if (@TypeOf(other) == Self) {
        return std.mem.eql(u8, slice, other.bytes());
    }

    const info = @typeInfo(@TypeOf(other));
    if (info == .Pointer) {
        return std.mem.eql(u8, slice, other[0..other.len]);
    }

    return false;
}

/// isAsciiStr checks if a string (`[]const uu`) is composed solely of ASCII characters.
pub fn isAsciiStr(str: []const u8) !bool {
    // Shamelessly stolen from std.unicode.
    const N = @sizeOf(usize);
    const MASK = 0x80 * (std.math.maxInt(usize) / 0xff);

    var i: usize = 0;
    while (i < str.len) {
        // Fast path for ASCII sequences
        while (i + N <= str.len) : (i += N) {
            const v = mem.readIntNative(usize, str[i..][0..N]);
            if (v & MASK != 0) {
                return false;
            }
        }

        if (i < str.len) {
            const n = try unicode.utf8ByteSequenceLength(str[i]);
            if (i + n > str.len) return error.TruncatedInput;

            switch (n) {
                1 => {}, // ASCII
                else => return false,
            }

            i += n;
        }
    }

    return true;
}

/// trimLeft removes `str` from the left of this Zigstr, mutating it.
pub fn trimLeft(self: *Self, str: []const u8) !void {
    var list = try self.list.asList();
    const trimmed = mem.trimLeft(u8, list.items, str);
    for (trimmed, 0..) |b, i| {
        list.items[i] = b;
    }
    list.items.len = trimmed.len;
}

/// trimRight removes `str` from the right of this Zigstr, mutating it.
pub fn trimRight(self: *Self, str: []const u8) !void {
    var list = try self.list.asList();
    const trimmed = mem.trimRight(u8, list.items, str);
    for (trimmed, 0..) |b, i| {
        list.items[i] = b;
    }
    list.items.len = trimmed.len;
}

/// trim removes `str` from both the left and right of this Zigstr, mutating it.
pub fn trim(self: *Self, str: []const u8) !void {
    var list = try self.list.asList();
    const trimmed = mem.trim(u8, list.items, str);
    for (trimmed, 0..) |b, i| {
        list.items[i] = b;
    }
    list.items.len = trimmed.len;
}

/// dropLeft removes `n` graphemes from the left of this Zigstr, mutating it.
pub fn dropLeft(self: *Self, n: usize) !void {
    const gcs = try self.graphemes(self.allocator);
    defer self.allocator.free(gcs);

    if (n >= gcs.len) return error.IndexOutOfBounds;

    const offset = gcs[n].offset;
    var list = try self.list.asList();
    mem.rotate(u8, list.items, offset);
    list.shrinkRetainingCapacity(list.items.len - offset);
}

test "Zigstr dropLeft" {
    var str = try fromConstBytes(std.testing.allocator, "Héllo");
    defer str.deinit();

    try str.dropLeft(4);
    try expect(str.eql("o"));
}

/// dropRight removes `n` graphemes from the right of this Zigstr, mutating it.
pub fn dropRight(self: *Self, n: usize) !void {
    const gcs = try self.graphemes(self.allocator);
    defer self.allocator.free(gcs);

    if (n > gcs.len) return error.IndexOutOfBounds;

    if (n == gcs.len) {
        try self.reset("");
        return;
    }

    const offset = gcs[gcs.len - n].offset;
    var list = try self.list.asList();
    list.shrinkRetainingCapacity(offset);
}

test "Zigstr dropRight" {
    var str = try fromConstBytes(std.testing.allocator, "Héllo");
    defer str.deinit();

    try str.dropRight(4);
    try expect(str.eql("H"));
}

/// inserts `str` at grapheme index `n`. This operation is O(n).
pub fn insert(self: *Self, str: []const u8, n: usize) !void {
    const gcs = try self.graphemes(self.allocator);
    defer self.allocator.free(gcs);

    var list = try self.list.asList();
    if (n < gcs.len) {
        try list.insertSlice(gcs[n].offset, str);
    } else {
        try list.insertSlice(gcs[n - 1].offset + gcs[n - 1].bytes.len, str);
    }
}

test "Zigstr insertions" {
    var str = try fromConstBytes(std.testing.allocator, "Hélo");
    defer str.deinit();

    try str.insert("l", 3);
    try expect(str.eql("Héllo"));
    try str.insert("Hey ", 0);
    try expect(str.eql("Hey Héllo"));
    try str.insert("!", try str.graphemeLen());
    try expect(str.eql("Hey Héllo!"));
}

/// indexOf returns the index of `needle` in this Zigstr or null if not found.
pub fn indexOf(self: Self, needle: []const u8) !?usize {
    if (needle.len > 0) {
        const slice = self.bytes();

        if (mem.indexOf(u8, slice, needle)) |end| {
            var i: usize = 0;
            var iter = try GraphemeIterator.init(slice[0..end]);
            while (iter.next()) |_| : (i += 1) {} else return i;
        }
    }

    return null;
}

/// containes ceonvenience method to check if `str` is a substring of this Zigstr.
pub fn contains(self: Self, str: []const u8) !bool {
    return (try self.indexOf(str)) != null;
}

/// lastIndexOf returns the index of `needle` in this Zigstr starting from the end, or null if not found.
pub fn lastIndexOf(self: Self, needle: []const u8) !?usize {
    if (needle.len > 0) {
        const slice = self.bytes();

        if (mem.lastIndexOf(u8, slice, needle)) |end| {
            var i: usize = 0;
            var iter = try GraphemeIterator.init(slice[0..end]);
            while (iter.next()) |_| : (i += 1) {} else return i;
        }
    }

    return null;
}

/// count returns the number of `needle`s in this Zigstr.
pub fn count(self: Self, needle: []const u8) usize {
    return mem.count(u8, self.bytes(), needle);
}

/// tokenIter returns an iterator on tokens resulting from splitting this Zigstr at any byte in `delim`.
/// Semantics are that of `std.mem.tokenize`.
pub fn tokenIter(self: Self, delim: []const u8) mem.TokenIterator(u8, .any) {
    return mem.tokenizeAny(u8, self.bytes(), delim);
}

/// tokenize returns a slice of tokens resulting from splitting this Zigstr at any byte in `delim`.
/// Caller must free returned slice.
pub fn tokenize(self: Self, allocator: mem.Allocator, delim: []const u8) ![][]const u8 {
    var ts = std.ArrayList([]const u8).init(allocator);
    defer ts.deinit();

    var iter = self.tokenIter(delim);
    while (iter.next()) |t| try ts.append(t);

    return ts.toOwnedSlice();
}

/// splitIter returns an iterator on substrings resulting from splitting this Zigstr at any byte in `delim`.
/// Semantics are that of `std.mem.split`.
pub fn splitIter(self: Self, delim: []const u8) mem.SplitIterator(u8, .any) {
    return mem.splitAny(u8, self.bytes(), delim);
}

/// split returns a slice of substrings resulting from splitting this Zigstr at any byte in `delim`.
/// Caller must free returned slice.
pub fn split(self: Self, allocator: mem.Allocator, delim: []const u8) ![][]const u8 {
    const slice = self.bytes();
    var ss = try std.ArrayList([]const u8).initCapacity(allocator, slice.len);
    defer ss.deinit();

    var iter = mem.splitAny(u8, slice, delim);
    while (iter.next()) |s| {
        ss.appendAssumeCapacity(s);
    }

    return ss.toOwnedSlice();
}

/// lineIter returns an iterator of lines separated by \n in this Zigstr.
pub fn lineIter(self: Self) mem.SplitIterator(u8, .any) {
    return self.splitIter("\n");
}

/// lines returns a slice of substrings resulting from splitting this Zigstr at every \n.
/// Caller must free returned slice.
pub fn lines(self: Self, allocator: mem.Allocator) ![][]const u8 {
    return self.split(allocator, "\n");
}

test "Zigstr lines" {
    var allocator = std.testing.allocator;
    var str = try fromConstBytes(allocator, "Hello\nWorld");
    defer str.deinit();

    var iter = str.lineIter();
    try expectEqualStrings(iter.next().?, "Hello");
    try expectEqualStrings(iter.next().?, "World");

    var lines_array = try str.lines(allocator);
    defer allocator.free(lines_array);
    try expectEqualStrings(lines_array[0], "Hello");
    try expectEqualStrings(lines_array[1], "World");
}

/// reverses the grapheme clusters in this Zigstr, mutating it.
pub fn reverse(self: *Self) !void {
    const gcs = try self.graphemes(self.allocator);
    defer self.allocator.free(gcs);

    var list = try std.ArrayList(u8).initCapacity(self.allocator, self.byteLen());
    defer list.deinit();
    var gc_index: isize = @as(isize, @intCast(gcs.len)) - 1;

    while (gc_index >= 0) : (gc_index -= 1) {
        list.appendSliceAssumeCapacity(gcs[@intCast(gc_index)].bytes);
    }

    self.list.deinit();
    self.list = CowList(u8).initOwned(self.allocator, try list.toOwnedSlice());
}

test "Zigstr reverse" {
    var str = try fromConstBytes(std.testing.allocator, "Héllo 😊");
    defer str.deinit();

    try str.reverse();
    try expect(str.eql("😊 olléH"));
}

/// startsWith returns true if this Zigstr starts with `str`.
pub fn startsWith(self: Self, str: []const u8) bool {
    return mem.startsWith(u8, self.bytes(), str);
}

/// endsWith returns true if this Zigstr ends with `str`.
pub fn endsWith(self: Self, str: []const u8) bool {
    return mem.endsWith(u8, self.bytes(), str);
}

/// concatAll appends each string in `others` to this Zigstr, mutating it.
pub fn concatAll(self: *Self, others: []const []const u8) !void {
    for (others) |o| {
        var list = try self.list.asList();
        try list.appendSlice(o);
    }
}

/// concat appends `other` to this Zigstr, mutating it.
pub fn concat(self: *Self, other: []const u8) !void {
    try self.concatAll(&[1][]const u8{other});
}

/// replace all occurrences of `needle` with `replacement`, mutating this Zigstr. Returns the total
/// replacements made.
pub fn replace(self: *Self, needle: []const u8, replacement: []const u8) !usize {
    var list = try self.list.asList();
    const len = mem.replacementSize(u8, list.items, needle, replacement);
    var buf = try self.allocator.alloc(u8, len);
    defer self.allocator.free(buf);
    const replacements = mem.replace(u8, list.items, needle, replacement, buf);
    try list.replaceRange(0, list.items.len, buf);

    return replacements;
}

/// remove `str` from this Zigstr, mutating it.
pub fn remove(self: *Self, str: []const u8) !void {
    _ = try self.replace(str, "");
}

test "Zigstr remove" {
    var str = try fromConstBytes(std.testing.allocator, "HiHello");
    defer str.deinit();

    try str.remove("Hi");
    try expect(str.eql("Hello"));
    try str.remove("Hello");
    try expect(str.eql(""));
}

/// append adds `cp` to the end of this Zigstr, mutating it.
pub fn append(self: *Self, cp: u21) !void {
    var buf: [4]u8 = undefined;
    const len = try unicode.utf8Encode(cp, &buf);
    try self.concat(buf[0..len]);
}

/// append adds `cp` to the end of this Zigstr, mutating it.
pub fn appendAll(self: *Self, cp_list: []const u21) !void {
    var cp_bytes = try std.ArrayList(u8).initCapacity(self.allocator, cp_list.len * 4);
    defer cp_bytes.deinit();

    var buf: [4]u8 = undefined;
    for (cp_list) |cp| {
        const len = try unicode.utf8Encode(cp, &buf);
        cp_bytes.appendSliceAssumeCapacity(buf[0..len]);
    }

    try self.concat(cp_bytes.items);
}

/// isEmpty returns true if this Zigstr has no bytes.
pub fn isEmpty(self: Self) bool {
    return self.byteLen() == 0;
}

/// isBlank returns true if this Zigstr consits of whitespace only .
pub fn isBlank(self: *Self) !bool {
    const cps = try self.codePoints(self.allocator);
    defer self.allocator.free(cps);

    return for (cps) |cp| {
        if (!prop_list.isWhiteSpace(cp)) break false;
    } else true;
}

test "Zigstr isBlank" {
    var str = try fromConstBytes(std.testing.allocator, " \t   ");
    defer str.deinit();

    try expect(try str.isBlank());
    try str.reset(" a b \t");
    try expect(!try str.isBlank());
}

/// chomp will remove trailing \n or \r\n from this Zigstr, mutating it.
pub fn chomp(self: *Self) !void {
    if (self.isEmpty()) return;

    var list = try self.list.asList();
    const len = list.items.len;
    const last = list.items[len - 1];
    if (last == '\r' or last == '\n') {
        // CR
        var chomp_size: usize = 1;
        if (len > 1 and last == '\n' and list.items[list.items.len - 2] == '\r') chomp_size = 2; // CR+LF
        list.shrinkRetainingCapacity(len - chomp_size);
    }
}

/// byteAt returns the byte at index `i`.
pub fn byteAt(self: Self, i: isize) !u8 {
    const slice = self.bytes();

    if (i >= slice.len) return error.IndexOutOfBounds;

    if (i < 0) {
        if (-%i > slice.len) return error.IndexOutOfBounds;
        return slice[slice.len - @as(usize, @intCast(-i))];
    }

    return slice[@intCast(i)];
}

/// codePointAt returns the `i`th code point.
pub fn codePointAt(self: *Self, i: isize) !u21 {
    const cps = try self.codePoints(self.allocator);
    defer self.allocator.free(cps);

    if (i >= cps.len) return error.IndexOutOfBounds;
    if (i < 0) {
        if (-%i > cps.len) return error.IndexOutOfBounds;
        return cps[cps.len - @as(usize, @intCast(-i))];
    }

    return cps[@intCast(i)];
}

/// graphemeAt returns the `i`th grapheme cluster.
pub fn graphemeAt(self: *Self, i: isize) !Grapheme {
    const gcs = try self.graphemes(self.allocator);
    defer self.allocator.free(gcs);

    if (i >= gcs.len) return error.IndexOutOfBounds;
    if (i < 0) {
        if (-%i > gcs.len) return error.IndexOutOfBounds;
        return gcs[gcs.len - @as(usize, @intCast(-i))];
    }

    return gcs[@intCast(i)];
}

/// byteSlice returnes the bytes from this Zigstr in the specified range from `start` to `end` - 1.
pub fn byteSlice(self: Self, start: usize, end: usize) ![]const u8 {
    const slice = self.bytes();
    if (end <= start) return error.InvalidRange;
    if (start >= slice.len or end > slice.len) return error.IndexOutOfBounds;

    return slice[start..end];
}

/// codePointSlice returnes the code points from this Zigstr in the specified range from `start` to `end` - 1.
/// Caller must free returned slice.
pub fn codePointSlice(self: *Self, allocator: mem.Allocator, start: usize, end: usize) ![]u21 {
    if (end <= start) return error.InvalidRange;

    const cps = try self.codePoints(allocator);
    defer allocator.free(cps);

    if (start >= cps.len or end > cps.len) return error.IndexOutOfBounds;

    var rcps = try std.ArrayList(u21).initCapacity(allocator, end - start);
    defer rcps.deinit();

    for (cps[start..end]) |cp| {
        rcps.appendAssumeCapacity(cp);
    }

    return rcps.toOwnedSlice();
}

/// graphemeSlice returnes the grapheme clusters from this Zigstr in the specified range from `start` to `end` - 1.
/// Caller must free returned slice.
pub fn graphemeSlice(self: *Self, allocator: mem.Allocator, start: usize, end: usize) ![]Grapheme {
    if (end <= start) return error.InvalidRange;

    const gcs = try self.graphemes(allocator);
    defer allocator.free(gcs);

    if (start >= gcs.len or end > gcs.len) return error.IndexOutOfBounds;

    var rgcs = try std.ArrayList(Grapheme).initCapacity(allocator, end - start);
    defer rgcs.deinit();

    for (gcs[start..end]) |gc| {
        rgcs.appendAssumeCapacity(gc);
    }

    return rgcs.toOwnedSlice();
}

/// substr returns a byte slice representing the grapheme range starting at `start` grapheme index
/// up to `end` grapheme index - 1.
pub fn substr(self: *Self, start: usize, end: usize) ![]const u8 {
    if (end <= start) return error.InvalidRange;
    const slice = self.bytes();

    if (try isAsciiStr(slice)) {
        if (start >= slice.len or end > slice.len) return error.IndexOutOfBounds;
        return slice[start..end];
    }

    const gcs = try self.graphemes(self.allocator);
    defer self.allocator.free(gcs);

    if (start >= gcs.len or end > gcs.len) return error.IndexOutOfBounds;

    return slice[gcs[start].offset..gcs[end].offset];
}

/// isLower detects if all the code points in this Zigstr are lowercase.
pub fn isLower(self: *Self) !bool {
    return ziglyph.isLowerStr(self.bytes());
}

/// toLower converts this Zigstr to lowercase, mutating it.
pub fn toLower(self: *Self) !void {
    const lower = try ziglyph.toLowerStr(self.allocator, self.bytes());
    defer self.allocator.free(lower);
    try self.reset(lower);
}

/// isUpper detects if all the code points in this Zigstr are uppercase.
pub fn isUpper(self: *Self) !bool {
    return ziglyph.isUpperStr(self.bytes());
}

/// toUpper converts this Zigstr to uppercase, mutating it.
pub fn toUpper(self: *Self) !void {
    const upper = try ziglyph.toUpperStr(self.allocator, self.bytes());
    defer self.allocator.free(upper);
    try self.reset(upper);
}

/// toTitle converts this Zigstr to titlecase, mutating it.
pub fn toTitle(self: *Self) !void {
    const title = try ziglyph.toTitleStr(self.allocator, self.bytes());
    defer self.allocator.free(title);
    try self.reset(title);
}

/// format implements the `std.fmt` format interface for printing types.
pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    _ = fmt;
    _ = options;
    _ = try writer.print("{s}", .{self.bytes()});
}

/// parseInt tries to parse this Zigstr as an integer of type `T` in base `radix`.
pub fn parseInt(self: Self, comptime T: type, radix: u8) !T {
    return std.fmt.parseInt(T, self.bytes(), radix);
}

/// parseFloat tries to parse this Zigstr as an floating point number of type `T`.
pub fn parseFloat(self: Self, comptime T: type) !T {
    return std.fmt.parseFloat(T, self.bytes());
}

test "Zigstr parse numbers" {
    var str = try fromConstBytes(std.testing.allocator, "2112");
    defer str.deinit();

    try expectEqual(@as(u16, 2112), try str.parseInt(u16, 10));
    try expectEqual(@as(i16, 2112), try str.parseInt(i16, 10));
    try expectEqual(@as(f16, 2112.0), try str.parseFloat(f16));
}

/// repeats the contents of this Zigstr `n` times, mutating it.
pub fn repeat(self: *Self, n: usize) !void {
    if (n == 1) return;

    const slice = self.bytes();
    var list = try std.ArrayList(u8).initCapacity(self.allocator, slice.len * n);
    defer list.deinit();

    var i: usize = 0;
    while (i < n) : (i += 1) {
        list.appendSliceAssumeCapacity(slice);
    }

    self.list.deinit();
    self.list = CowList(u8).initOwned(self.allocator, try list.toOwnedSlice());
}

test "Zigstr repeat" {
    var str = try fromConstBytes(std.testing.allocator, "*");
    defer str.deinit();

    try str.repeat(10);
    try expect(str.eql("**********"));
    try str.repeat(1);
    try expect(str.eql("**********"));
    try str.repeat(0);
    try expect(str.eql(""));
}

/// parseBool parses this Zigstr as either true or false.
pub fn parseBool(self: Self) !bool {
    const slice = self.bytes();
    if (mem.eql(u8, slice, "true")) return true;
    if (mem.eql(u8, slice, "false")) return false;

    return error.ParseBoolError;
}

/// parseTruthy parses this Zigstr as a *truthy* value:
/// * True and T in any case combination are true.
/// * False and F in any case combination are false.
/// * 0 is false, 1 is true.
/// * Yes, Y, and On in any case combination are true.
/// * No, N, and Off in any case combination are false.
pub fn parseTruthy(self: Self) !bool {
    var lstr = try fromConstBytes(self.allocator, self.bytes());
    defer lstr.deinit();

    try lstr.toLower();
    const slice = lstr.bytes();
    // True
    if (mem.eql(u8, slice, "true")) return true;
    if (mem.eql(u8, slice, "t")) return true;
    if (mem.eql(u8, slice, "on")) return true;
    if (mem.eql(u8, slice, "yes")) return true;
    if (mem.eql(u8, slice, "y")) return true;
    if (mem.eql(u8, slice, "1")) return true;
    // False
    if (mem.eql(u8, slice, "false")) return false;
    if (mem.eql(u8, slice, "f")) return false;
    if (mem.eql(u8, slice, "off")) return false;
    if (mem.eql(u8, slice, "no")) return false;
    if (mem.eql(u8, slice, "n")) return false;
    if (mem.eql(u8, slice, "0")) return false;

    return error.ParseTruthyError;
}

test "Zigstr parse bool truthy" {
    var str = try fromConstBytes(std.testing.allocator, "true");
    defer str.deinit();

    try expect(try str.parseBool());
    try expect(try str.parseTruthy());
    try str.reset("false");
    try expect(!try str.parseBool());
    try expect(!try str.parseTruthy());

    try str.reset("true");
    try expect(try str.parseTruthy());
    try str.reset("t");
    try expect(try str.parseTruthy());
    try str.reset("on");
    try expect(try str.parseTruthy());
    try str.reset("yes");
    try expect(try str.parseTruthy());
    try str.reset("y");
    try expect(try str.parseTruthy());
    try str.reset("1");
    try expect(try str.parseTruthy());
    try str.reset("TrUe");
    try expect(try str.parseTruthy());

    try str.reset("false");
    try expect(!try str.parseTruthy());
    try str.reset("f");
    try expect(!try str.parseTruthy());
    try str.reset("off");
    try expect(!try str.parseTruthy());
    try str.reset("no");
    try expect(!try str.parseTruthy());
    try str.reset("n");
    try expect(!try str.parseTruthy());
    try str.reset("0");
    try expect(!try str.parseTruthy());
    try str.reset("FaLsE");
    try expect(!try str.parseTruthy());
}

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectError = std.testing.expectError;

test "Zigstr code points" {
    var allocator = std.testing.allocator;
    var str = try fromConstBytes(allocator, "Héllo");
    defer str.deinit();

    var cp_iter = str.codePointIter();
    var want = [_]u21{ 'H', 0x00E9, 'l', 'l', 'o' };
    var i: usize = 0;
    while (cp_iter.next()) |cp| : (i += 1) {
        try expectEqual(want[i], cp.scalar);
    }

    const cps = try str.codePoints(allocator);
    defer allocator.free(cps);
    try expectEqualSlices(u21, &want, cps);

    try expectEqual(@as(usize, 6), str.byteLen());
    try expectEqual(@as(usize, 5), try str.codePointLen());
}

test "Zigstr graphemes" {
    var allocator = std.testing.allocator;
    var str = try fromConstBytes(allocator, "Héllo");
    defer str.deinit();

    var giter = try str.graphemeIter();
    var want = [_][]const u8{ "H", "é", "l", "l", "o" };
    var i: usize = 0;
    while (giter.next()) |gc| : (i += 1) {
        try expect(gc.eql(want[i]));
    }

    const gcs = try str.graphemes(allocator);
    defer allocator.free(gcs);

    for (gcs, 0..) |gc, j| {
        try expect(gc.eql(want[j]));
    }

    try expectEqual(@as(usize, 6), str.byteLen());
    try expectEqual(@as(usize, 5), try str.graphemeLen());
}

test "Zigstr copy" {
    var str1 = try fromConstBytes(std.testing.allocator, "Zig");
    defer str1.deinit();

    var str2 = try str1.copy(std.testing.allocator);
    defer str2.deinit();

    try expect(str1.eql(str2));
    try expect(str2.eql("Zig"));
}

test "Zigstr isAsciiStr" {
    try expect(try isAsciiStr("Hello!"));
    try expect(!try isAsciiStr("Héllo!"));
}

test "Zigstr trimLeft" {
    var str = try fromConstBytes(std.testing.allocator, "    Hello");
    defer str.deinit();

    try str.trimLeft(" ");
    try expect(str.eql("Hello"));
}

test "Zigstr trimRight" {
    var str = try fromConstBytes(std.testing.allocator, "Hello    ");
    defer str.deinit();

    try str.trimRight(" ");
    try expect(str.eql("Hello"));
}

test "Zigstr trim" {
    var str = try fromConstBytes(std.testing.allocator, "   Hello   ");
    defer str.deinit();

    try str.trim(" ");
    try expect(str.eql("Hello"));
}

test "Zigstr indexOf" {
    var str = try fromConstBytes(std.testing.allocator, "😊 Héllo world");
    defer str.deinit();

    try expectEqual(try str.indexOf("😊"), 0);
    try expectEqual(try str.indexOf("l"), 4);
    try expectEqual(try str.indexOf("lo"), 5);
    try expectEqual(try str.indexOf("orld"), 9);
    try expectEqual(try str.indexOf("z"), null);
    try expectEqual(try str.indexOf(""), null);
    try expect(try str.contains("l"));
    try expect(!try str.contains("z"));
}

test "Zigstr lastIndexOf" {
    var str = try fromConstBytes(std.testing.allocator, "Héllo lol 😊");
    defer str.deinit();

    try expectEqual(try str.lastIndexOf("l"), 8);
    try expectEqual(try str.lastIndexOf("lo"), 6);
    try expectEqual(try str.lastIndexOf(" 😊"), 9);
    try expectEqual(try str.lastIndexOf("😊"), 10);
    try expectEqual(try str.lastIndexOf("z"), null);
    try expectEqual(try str.lastIndexOf(""), null);
}

test "Zigstr count" {
    var str = try fromConstBytes(std.testing.allocator, "Hello");
    defer str.deinit();

    try expectEqual(str.count("l"), 2);
    try expectEqual(str.count("ll"), 1);
    try expectEqual(str.count("z"), 0);
}

test "Zigstr tokenize" {
    var allocator = std.testing.allocator;
    var str = try fromConstBytes(allocator, " Hello World ");
    defer str.deinit();

    var iter = str.tokenIter(" ");
    try expectEqualStrings("Hello", iter.next().?);
    try expectEqualStrings("World", iter.next().?);
    try expect(iter.next() == null);

    var ts = try str.tokenize(allocator, " ");
    defer allocator.free(ts);
    try expectEqual(@as(usize, 2), ts.len);
    try expectEqualStrings("Hello", ts[0]);
    try expectEqualStrings("World", ts[1]);
}

test "Zigstr split" {
    var allocator = std.testing.allocator;
    var str = try fromConstBytes(allocator, " Hello World ");
    defer str.deinit();

    var iter = str.splitIter(" ");
    try expectEqualStrings("", iter.next().?);
    try expectEqualStrings("Hello", iter.next().?);
    try expectEqualStrings("World", iter.next().?);
    try expectEqualStrings("", iter.next().?);
    try expect(iter.next() == null);

    var ss = try str.split(allocator, " ");
    defer allocator.free(ss);
    try expectEqual(@as(usize, 4), ss.len);
    try expectEqualStrings("", ss[0]);
    try expectEqualStrings("Hello", ss[1]);
    try expectEqualStrings("World", ss[2]);
    try expectEqualStrings("", ss[3]);
}

test "Zigstr startsWith" {
    var str = try fromConstBytes(std.testing.allocator, "Hello World");
    defer str.deinit();

    try expect(str.startsWith("Hell"));
    try expect(!str.startsWith("Zig"));
}

test "Zigstr endsWith" {
    var str = try fromConstBytes(std.testing.allocator, "Hello World");
    defer str.deinit();

    try expect(str.endsWith("World"));
    try expect(!str.endsWith("Zig"));
}

test "Zigstr concat" {
    var str = try fromConstBytes(std.testing.allocator, "Hello");
    defer str.deinit();

    try str.concat(" World");
    try expect(str.eql("Hello World"));
    var others = [_][]const u8{ " is", " the", " tradition!" };
    try str.concatAll(&others);
    try expect(str.eql("Hello World is the tradition!"));
}

test "Zigstr replace" {
    var str = try fromConstBytes(std.testing.allocator, "Hello");
    defer str.deinit();

    var replacements = try str.replace("l", "z");
    try expectEqual(@as(usize, 2), replacements);
    try expect(str.eql("Hezzo"));

    replacements = try str.replace("z", "");
    try expectEqual(@as(usize, 2), replacements);
    try expect(str.eql("Heo"));
}

test "Zigstr append" {
    var str = try fromConstBytes(std.testing.allocator, "Hell");
    defer str.deinit();

    try str.append('o');
    try expectEqual(@as(usize, 5), str.byteLen());
    try expect(str.eql("Hello"));
    try str.appendAll(&[_]u21{ ' ', 'W', 'o', 'r', 'l', 'd' });
    try expectEqual(@as(usize, 11), str.byteLen());
    try expect(str.eql("Hello World"));
}

test "Zigstr chomp" {
    var str = try fromConstBytes(std.testing.allocator, "Hello\n");
    defer str.deinit();

    try str.chomp();
    try expectEqual(@as(usize, 5), str.byteLen());
    try expect(str.eql("Hello"));

    try str.reset("Hello\r");
    try str.chomp();
    try expectEqual(@as(usize, 5), str.byteLen());
    try expect(str.eql("Hello"));

    try str.reset("Hello\r\n");
    try str.chomp();
    try expectEqual(@as(usize, 5), str.byteLen());
    try expect(str.eql("Hello"));
}

test "Zigstr xAt" {
    var str = try fromConstBytes(std.testing.allocator, "H\u{0065}\u{0301}llo");
    defer str.deinit();

    try expectEqual(try str.byteAt(2), 0x00CC);
    try expectEqual(try str.byteAt(-5), 0x00CC);
    try expectError(error.IndexOutOfBounds, str.byteAt(7));
    try expectError(error.IndexOutOfBounds, str.byteAt(-8));
    try expectEqual(try str.codePointAt(1), 0x0065);
    try expectEqual(try str.codePointAt(-5), 0x0065);
    try expectError(error.IndexOutOfBounds, str.codePointAt(6));
    try expectError(error.IndexOutOfBounds, str.codePointAt(-7));
    try expect((try str.graphemeAt(1)).eql("\u{0065}\u{0301}"));
    try expect((try str.graphemeAt(-4)).eql("\u{0065}\u{0301}"));
    try expectError(error.IndexOutOfBounds, str.graphemeAt(5));
    try expectError(error.IndexOutOfBounds, str.graphemeAt(-6));
}

test "Zigstr extractions" {
    var allocator = std.testing.allocator;
    var str = try fromConstBytes(allocator, "H\u{0065}\u{0301}llo");
    defer str.deinit();

    // Slices
    const byte_slice = try str.byteSlice(1, 4);
    try expectEqualSlices(u8, byte_slice, "\u{0065}\u{0301}");

    const cps = try str.codePointSlice(allocator, 1, 3);
    defer allocator.free(cps);
    try expectEqualSlices(u21, cps, &[_]u21{ '\u{0065}', '\u{0301}' });

    const gcs = try str.graphemeSlice(allocator, 1, 2);
    defer allocator.free(gcs);
    try expect(gcs[0].eql("\u{0065}\u{0301}"));

    // Substrings
    var sub = try str.substr(1, 2);
    try expectEqualStrings("\u{0065}\u{0301}", sub);

    try expectEqualStrings(byte_slice, sub);
}

test "Zigstr casing" {
    var str = try fromConstBytes(std.testing.allocator, "Héllo! 123");
    defer str.deinit();

    try expect(!try str.isLower());
    try expect(!try str.isUpper());
    try str.toLower();
    try expect(try str.isLower());
    try expect(str.eql("héllo! 123"));
    try str.toUpper();
    try expect(try str.isUpper());
    try expect(str.eql("HÉLLO! 123"));
}

test "Zigstr format" {
    var str = try fromConstBytes(std.testing.allocator, "Héllo 😊");
    defer str.deinit();

    std.debug.print("{}\n", .{str});
}
