
CREATE TABLE IF NOT EXISTS poorly_clustered_tables
(
    run_timestamp            TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    full_table_name          VARCHAR(400),
    auto_clustering_on       VARCHAR(100),
    clustering_key           VARCHAR(400),
    average_depth            DECIMAL(10,2),
    average_overlaps         DECIMAL(10,2),
    partition_count          INT,
    constant_partition_count INT,
    table_size_gb            DECIMAL(10,2),
    cluster_info             VARIANT
);
 
CREATE OR REPLACE PROCEDURE find_poorly_clustered_tables
(
    min_partition_count  INT           DEFAULT 400,
    min_table_size_gb    INT           DEFAULT 1,
    max_average_depth    DECIMAL(10,2) DEFAULT 10
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    run_timestamp        TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP();
    full_table_name      VARCHAR(384);
    auto_clustering_on   VARCHAR(100);
    clustering_key       VARCHAR(400);
    table_size_gb        DECIMAL(10,2);
    average_depth        DECIMAL(10,2);
    average_overlaps     DECIMAL(10,2);   
    median_depth         DECIMAL(10,2);
    partition_count      INT;
    constant_partition_count INT;
    result_message       VARCHAR DEFAULT '';    
 
    table_cursor CURSOR FOR 
        SELECT DISTINCT 
            TABLE_CATALOG || '.' || TABLE_SCHEMA || '.' || TABLE_NAME AS full_table_name,
            BYTES / POWER(1024, 3) AS table_size_gb,
            AUTO_CLUSTERING_ON AS auto_clustering_on,
            clustering_key
        FROM 
            SNOWFLAKE.ACCOUNT_USAGE.TABLES
        WHERE 
            CLUSTERING_KEY IS NOT NULL
            AND (TABLE_TYPE = 'BASE TABLE' OR TABLE_TYPE = 'MATERIALIZED VIEW')
        ORDER BY
            full_table_name;
 
BEGIN
    OPEN table_cursor;
 
    LOOP
        FETCH table_cursor INTO full_table_name, table_size_gb, auto_clustering_on, clustering_key;
       
        IF (full_table_name IS NULL) THEN
            BREAK;
        END IF;
 
        IF (table_size_gb < min_table_size_gb) THEN
            CONTINUE;
        END IF;
 
        BEGIN
            CREATE OR REPLACE TEMPORARY TABLE tmp_clustering_info(info VARIANT);
            INSERT INTO tmp_clustering_info
            SELECT PARSE_JSON(SYSTEM$CLUSTERING_INFORMATION(:full_table_name));
 
            SELECT
                info:average_depth::DECIMAL(10,2),
                info:average_overlaps::DECIMAL(10,2),
                info:total_constant_partition_count::INT,
                info:total_partition_count::INT
            INTO :average_depth, :average_overlaps, :constant_partition_count, :partition_count
            FROM tmp_clustering_info;
 
            IF (partition_count < min_partition_count OR average_depth <= max_average_depth) THEN
                CONTINUE;
            END IF;
 
            CREATE OR REPLACE TEMPORARY TABLE tmp_partition_depth_histogram (depth INT, partition_count INT);
            INSERT INTO tmp_partition_depth_histogram (depth, partition_count)
            SELECT f.key::INT, f.value::INT
            FROM tmp_clustering_info, TABLE(FLATTEN(INPUT => info, PATH => 'partition_depth_histogram')) f;
 
            SELECT MIN(depth) 
            INTO :median_depth
            FROM
                (SELECT
                    depth,
                    SUM(partition_count) OVER (ORDER BY depth) AS cum_freq,
                    SUM(partition_count) OVER () AS total_freq
                FROM
                    tmp_partition_depth_histogram) t
            WHERE
                cum_freq >= total_freq / 2.0;
                   
            -- Left skewness test: average_depth < median_depth
            IF (constant_partition_count < partition_count/3.0 OR average_depth < median_depth) THEN
                
                INSERT INTO poorly_clustered_tables
                (run_timestamp, full_table_name, auto_clustering_on, clustering_key, average_depth, average_overlaps, partition_count, constant_partition_count, table_size_gb, cluster_info)
                SELECT :run_timestamp, :full_table_name, :auto_clustering_on, :clustering_key, :average_depth, :average_overlaps, :partition_count, :constant_partition_count, :table_size_gb, info 
                FROM tmp_clustering_info;
                
            END IF;
           
        EXCEPTION
            -- Record any tables with no access, or any other errors
            WHEN OTHER THEN
                result_message := result_message || SQLERRM || ' : ' || full_table_name || '\n';
                NULL;
        END;
 
    END LOOP;
 
    CLOSE table_cursor;
 
    RETURN result_message;
END;
$$;
 
-----------------------------------

-- Example use:

CALL find_poorly_clustered_tables();

-- Get latest results
select * from poorly_clustered_tables
where run_timestamp = (select max(run_timestamp) from poorly_clustered_tables)
order by average_depth desc;

-----------------------------------
