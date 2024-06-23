const ztest = @import("ztest");
const root = @import("root");
const expect = ztest.expect;

test {
    ztest.util.setUsingZtest();
    try expect(root.clientUsingZtest).isEqualTo(true);
}
