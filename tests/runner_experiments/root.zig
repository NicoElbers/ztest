test {
    const ztest = @import("ztest");
    const root = @import("root");
    const expect = ztest.expect;

    const is_ztest = ztest.utils.isUsingZtestRunner();

    if (!is_ztest) return;

    ztest.utils.setUsingZtest();
    try expect(root.clientUsingZtest).isEqualTo(true);
}
