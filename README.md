# Zigstr
⚠️ Attention! Zigstr has moved to Codeberg!
Visit the repo at: https://codeberg.org/dude_the_builder/zigstr and update your dependencies! This GitHub 
repo will be deleted on September 30, 2023 11:59 PM (AST-4).

A UTF-8 string type.

## Zig Version
This code will work with Zig version 0.11 stable.

## Adding Zigstr to your Project
Zigstr uses the Zig build system and official package manager, so integration is the same as any other Zig 
module. To track the main development branch, in `build.zig.zon` add:

```
.dependencies = .{
    .zigstr = .{
        .url = "https://github.com/jecolon/zigstr/archive/refs/tags/v0.11.1.tar.gz",
    },
},
```

and in your `build.zig`:

```
const zigstr = b.dependency("zigstr", .{
    .target = target,
    .optimize = optimize,
});

// exe, lib, tests, etc.
exe.addModule("zigstr", zigstr.module("zigstr"));
```

When you now try to build your project, the compiler will produce a hash mismatch error, indicating
the hash that you should add to `build.zig.zon` to make the build work.

To see available tags click [here](https://github.com/jecolon/zigstr/tags) and when you click
on a tag name, you'll see the link to the `tar.gz` file under **Assets**.

With all this, you can now `@import("zigstr")` in your project.

## Ownership
There are two possibilities when creating a new Zigstr:

* You own the bytes, requiring the `deinit` method to free them.
* You don't own the bytes, so `deinit` will not free them.

To create a Zigstr in each of these circumstances:

```zig
// Here the slice is []const u8.
var str = try Zigstr.fromConstBytes(allocator, "Hello");
defer str.deinit(); // still need `deinit` to free other resources, but not the passed-in bytes.

// Here the slice is []u8.
var str = try Zigstr.fromOwnedBytes(allocator, slice);
defer str.deinit(); // owned bytes will be freed.
```

## Usage Examples
```zig
const Zigstr = @import("Zigstr");

test "Zigstr README tests" {
    var allocator = std.testing.allocator;
    var str = try Zigstr.fromConstBytes(std.testing.allocator, "Héllo");
    defer str.deinit();

    // Byte count.
    try expectEqual(@as(usize, 6), str.byteLen());

    // Code point iteration.
    var cp_iter = str.codePointIter();
    var want = [_]u21{ 'H', 0x00E9, 'l', 'l', 'o' };

    var i: usize = 0;
    while (cp_iter.next()) |cp| : (i += 1) {
        try expectEqual(want[i], cp.code);
    }

    // Code point count.
    try expectEqual(@as(usize, 5), try str.codePointLen());

    // Collect all code points at once.
    const code_points = try str.codePoints(allocator);
    defer allocator.free(code_points);
    for (code_points, 0..) |cp, j| {
        try expectEqual(want[j], cp);
    }

    // Grapheme cluster iteration.
    var giter = try str.graphemeIter();
    const gc_want = [_][]const u8{ "H", "é", "l", "l", "o" };

    i = 0;
    while (giter.next()) |gc| : (i += 1) {
        try expect(gc.eql(str.bytes(), gc_want[i]));
    }

    // Collect all grapheme clusters at once.
    try expectEqual(@as(usize, 5), try str.graphemeLen());
    const gcs = try str.graphemes(allocator);
    defer allocator.free(gcs);

    for (gcs, 0..) |gc, j| {
        try expect(gc.eql(str.bytes(), gc_want[j]));
    }

    // Length by graphemes.
    try expectEqual(@as(usize, 5), try str.graphemeLen());

    // Indexing (with negative indexes too.)
    try expectEqual(try str.byteAt(0), 72); // H
    try expectEqual(try str.byteAt(-2), 108); // l
    try expectEqual(try str.codePointAt(0), 'H');
    try expectEqual(try str.codePointAt(-2), 'l');
    try expect((try str.graphemeAt(0)).eql(str.bytes(), "H"));
    try expect((try str.graphemeAt(-4)).eql(str.bytes(), "é"));

    // Copy
    var str2 = try str.copy(allocator);
    defer str2.deinit();
    try expect(str.eql(str2));
    try expect(str2.eql("Héllo"));

    // Empty and obtain owned slice of bytes.
    const bytes2 = try str2.toOwnedSlice();
    defer allocator.free(bytes2);
    try expect(str2.eql(""));
    try expectEqualStrings(bytes2, "Héllo");

    // Re-initialize a Zigstr.
    try str.reset("foo");

    // Equality
    try expect(str.eql("foo")); // exact
    try expect(!str.eql("fooo")); // lengths
    try expect(!str.eql("foó")); // combining marks
    try expect(!str.eql("Foo")); // letter case

    // Trimming.
    try str.reset("   Hello");
    try str.trimLeft(" ");
    try expect(str.eql("Hello"));

    try str.reset("Hello   ");
    try str.trimRight(" ");
    try expect(str.eql("Hello"));

    try str.reset("   Hello   ");
    try str.trim(" ");
    try expect(str.eql("Hello"));

    // indexOf / contains / lastIndexOf
    try str.reset("H\u{65}\u{301}llo"); // Héllo
    try expectEqual(str.indexOf("l"), 2);
    try expectEqual(str.indexOf("z"), null);
    try expect(str.contains("l"));
    try expect(!str.contains("z"));
    try expectEqual(str.lastIndexOf("l"), 3);
    try expectEqual(str.lastIndexOf("z"), null);

    // Count occurrences of substrings.
    try expectEqual(str.count("l"), 2);
    try expectEqual(str.count("ll"), 1);
    try expectEqual(str.count("z"), 0);

    // Tokenization
    try str.reset(" Hello World ");

    // Token iteration.
    var tok_iter = str.tokenIter(" ");
    try expectEqualStrings("Hello", tok_iter.next().?);
    try expectEqualStrings("World", tok_iter.next().?);
    try expect(tok_iter.next() == null);

    // Collect all tokens at once.
    var ts = try str.tokenize(allocator, " ");
    defer allocator.free(ts);
    try expectEqual(@as(usize, 2), ts.len);
    try expectEqualStrings("Hello", ts[0]);
    try expectEqualStrings("World", ts[1]);

    // Split
    var split_iter = str.splitIter(" ");
    try expectEqualStrings("", split_iter.next().?);
    try expectEqualStrings("Hello", split_iter.next().?);
    try expectEqualStrings("World", split_iter.next().?);
    try expectEqualStrings("", split_iter.next().?);
    try expect(split_iter.next() == null);

    // Collect all sub-strings at once.
    var ss = try str.split(allocator, " ");
    defer allocator.free(ss);
    try expectEqual(@as(usize, 4), ss.len);
    try expectEqualStrings("", ss[0]);
    try expectEqualStrings("Hello", ss[1]);
    try expectEqualStrings("World", ss[2]);
    try expectEqualStrings("", ss[3]);

    // Convenience methods for splitting on newline '\n'.
    try str.reset("Hello\nWorld");
    var iter = str.lineIter(); // line iterator
    try expectEqualStrings(iter.next().?, "Hello");
    try expectEqualStrings(iter.next().?, "World");

    var lines_array = try str.lines(allocator); // array of lines without ending \n.
    defer allocator.free(lines_array);
    try expectEqualStrings(lines_array[0], "Hello");
    try expectEqualStrings(lines_array[1], "World");

    // startsWith / endsWith
    try str.reset("Hello World");
    try expect(str.startsWith("Hell"));
    try expect(!str.startsWith("Zig"));
    try expect(str.endsWith("World"));
    try expect(!str.endsWith("Zig"));

    // Concatenation
    try str.reset("Hello");
    try str.concat(" World");
    try expect(str.eql("Hello World"));
    var others = [_][]const u8{ " is", " the", " tradition!" };
    try str.concatAll(&others);
    try expect(str.eql("Hello World is the tradition!"));

    // replace
    try str.reset("Hello");
    var replacements = try str.replace("l", "z");
    try expectEqual(@as(usize, 2), replacements);
    try expect(str.eql("Hezzo"));

    replacements = try str.replace("z", "");
    try expectEqual(@as(usize, 2), replacements);
    try expect(str.eql("Heo"));

    // Append code points.
    try str.reset("Hell");
    try str.append('o');
    try expectEqual(@as(usize, 5), str.byteLen());
    try expect(str.eql("Hello"));
    try str.appendAll(&[_]u21{ ' ', 'W', 'o', 'r', 'l', 'd' });
    try expect(str.eql("Hello World"));

    // Test for empty string.
    try expect(!str.isEmpty());

    // Test for whitespace only (blank) strings.
    try str.reset("  \t  ");
    try expect(try str.isBlank());
    try expect(!str.isEmpty());

    // Remove grapheme clusters (characters) from strings.
    try str.reset("Hello World");
    try str.dropLeft(6);
    try expect(str.eql("World"));
    try str.reset("Hello World");
    try str.dropRight(6);
    try expect(str.eql("Hello"));

    // Insert at a grapheme index.
    try str.insert("Hi", 0);
    try expect(str.eql("HiHello"));

    // Remove a sub-string.
    try str.remove("Hi");
    try expect(str.eql("Hello"));
    try str.remove("Hello");
    try expect(str.eql(""));

    // Repeat a string's content.
    try str.reset("*");
    try str.repeat(10);
    try expect(str.eql("**********"));
    try str.repeat(1);
    try expect(str.eql("**********"));
    try str.repeat(0);
    try expect(str.eql(""));

    // Reverse a string. Note correct handling of Unicode code point ordering.
    try str.reset("Héllo 😊");
    try str.reverse();
    try expect(str.eql("😊 olléH"));

    // You can also construct a Zigstr from coce points.
    const cp_array = [_]u21{ 0x68, 0x65, 0x6C, 0x6C, 0x6F }; // "hello"
    str.deinit();
    str = try Zigstr.fromCodePoints(allocator, &cp_array);
    try expect(str.eql("hello"));
    try expectEqual(str.codePointLen(), 5);

    // Also create a Zigstr from a slice of strings.
    str.deinit();
    str = try Zigstr.fromJoined(std.testing.allocator, &[_][]const u8{ "Hello", "World" }, " ");
    try expect(str.eql("Hello World"));

    // Chomp line breaks.
    try str.reset("Hello\n");
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

    // byteSlice, codePointSlice, graphemeSlice, substr
    try str.reset("H\u{0065}\u{0301}llo"); // Héllo
    const bytes = try str.byteSlice(1, 4);
    try expectEqualSlices(u8, bytes, "\u{0065}\u{0301}");

    const cps = try str.codePointSlice(allocator, 1, 3);
    defer allocator.free(cps);
    try expectEqualSlices(u21, cps, &[_]u21{ '\u{0065}', '\u{0301}' });

    const gs = try str.graphemeSlice(allocator, 1, 2);
    defer allocator.free(gs);
    try expect(gs[0].eql(str.bytes(), "\u{0065}\u{0301}"));

    // Substrings
    var sub = try str.substr(1, 2);
    try expectEqualStrings("\u{0065}\u{0301}", sub);

    try expectEqualStrings(bytes, sub);

    // Letter case detection.
    try str.reset("hello! 123");
    try expect(try str.isLower());
    try expect(!try str.isUpper());
    try str.reset("HELLO! 123");
    try expect(try str.isUpper());
    try expect(!try str.isLower());

    // Letter case conversion.
    try str.reset("Héllo World! 123\n");
    try str.toLower();
    try expect(str.eql("héllo world! 123\n"));
    try str.toUpper();
    try expect(str.eql("HÉLLO WORLD! 123\n"));
    try str.reset("tHe (mOviE) 2112\n");
    try str.toTitle();
    try expect(str.eql("The (Movie) 2112\n"));

    // Parsing content.
    try str.reset("123");
    try expectEqual(try str.parseInt(u8, 10), 123);
    try str.reset("123.456");
    try expectEqual(try str.parseFloat(f32), 123.456);
    try str.reset("true");
    try expect(try str.parseBool());

    // Truthy == True, T, Yes, Y, On in any letter case.
    // Not Truthy == False, F, No, N, Off in any letter case.
    try expect(try str.parseTruthy());
    try str.reset("TRUE");
    try expect(try str.parseTruthy());
    try str.reset("T");
    try expect(try str.parseTruthy());
    try str.reset("No");
    try expect(!try str.parseTruthy());
    try str.reset("off");
    try expect(!try str.parseTruthy());

    // Zigstr implements the std.fmt.format interface.
    std.debug.print("Zigstr: {}\n", .{str});
}
```
