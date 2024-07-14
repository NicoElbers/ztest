pub const parameterized_test = @import("parameterized_tests.zig");
pub const parameterizedWrap = parameterized_test.wrap;
pub const runAnyFunction = parameterized_test.callAnyFunction;
pub const runTest = parameterized_test.runTest;
pub const callAnyFunction = parameterized_test.callAnyFunction;

pub const runner_com = @import("runner_communication.zig");
pub const isUsingZtestRunner = runner_com.isUsingZtestRunner();
// FIXME: useless function
pub const setUsingZtest = runner_com.setUsingZtest;
pub const RunnerInfo = runner_com.RunnerInfo;
