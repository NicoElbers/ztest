const ztest = @import("ztest");
const root = @import("root");
const expect = ztest.expect;

// FIXME: Shitty test, remove
test {
    ztest.util.setUsingZtest();
    try expect(root.clientUsingZtest).isEqualTo(true);
}
