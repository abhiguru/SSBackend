-- =============================================
-- 36-pg-stat-statements.sql
-- Performance Monitoring: pg_stat_statements Extension
-- =============================================
-- Implements item 29 from the performance audit:
-- Enable pg_stat_statements for query performance monitoring

BEGIN;

-- Create the extension if it doesn't exist
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Grant access to authenticated users for monitoring
GRANT EXECUTE ON FUNCTION pg_stat_statements_reset() TO service_role;

-- Create a helper view for easy query analysis
CREATE OR REPLACE VIEW public.slow_queries AS
SELECT
    round((100 * total_exec_time / sum(total_exec_time) OVER ())::numeric, 2) AS percent,
    round(total_exec_time::numeric, 2) AS total_ms,
    calls,
    round(mean_exec_time::numeric, 2) AS mean_ms,
    round(min_exec_time::numeric, 2) AS min_ms,
    round(max_exec_time::numeric, 2) AS max_ms,
    round(stddev_exec_time::numeric, 2) AS stddev_ms,
    rows,
    query
FROM pg_stat_statements
WHERE total_exec_time > 0
ORDER BY total_exec_time DESC
LIMIT 50;

COMMENT ON VIEW public.slow_queries IS 'Top 50 queries by total execution time from pg_stat_statements';

-- Create a helper function to get query stats summary
CREATE OR REPLACE FUNCTION public.get_query_performance_summary()
RETURNS TABLE(
    total_queries BIGINT,
    total_time_ms NUMERIC,
    avg_time_ms NUMERIC,
    slowest_query_ms NUMERIC,
    most_called_count BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        COUNT(*)::BIGINT,
        ROUND(SUM(total_exec_time)::NUMERIC, 2),
        ROUND(AVG(mean_exec_time)::NUMERIC, 2),
        ROUND(MAX(max_exec_time)::NUMERIC, 2),
        MAX(calls)::BIGINT
    FROM pg_stat_statements
    WHERE calls > 0;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.get_query_performance_summary() TO service_role;

-- Create a function to reset stats (useful after optimizations)
CREATE OR REPLACE FUNCTION public.reset_query_stats()
RETURNS TEXT AS $$
BEGIN
    PERFORM pg_stat_statements_reset();
    RETURN 'Query statistics reset at ' || NOW()::TEXT;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.reset_query_stats() TO service_role;

COMMIT;
