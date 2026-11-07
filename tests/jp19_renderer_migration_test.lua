-- jp.19 adoption was retired by jp.20. Keep the former test entry point useful
-- for release scripts while validating the current one-time rollback policy.
return dofile("tests/jp20_renderer_migration_test.lua")
